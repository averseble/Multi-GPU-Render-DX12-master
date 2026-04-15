#include "pch.h"
#include "CrossAdapterGrassEmitter.h"
#include "GCommandList.h"
#include "MathHelper.h"
#include <algorithm>
#include "GameObject.h"
#include "Transform.h"

CrossAdapterGrassEmitter::CrossAdapterGrassEmitter(std::shared_ptr<GDevice> primeDev,
    const std::shared_ptr<GDevice>& secondDev,
    uint32_t grassCount, float worldSize,
    uint32_t lod0BladeCount, uint32_t lod1BladeCount)
    : primeDevice(primeDev), secondDevice(secondDev)
{
    emitterData.GrassCount = grassCount;
    emitterData.WorldSize = worldSize;
    emitterData.QuadSize = 10.0f;
    emitterData.WindStrength = 0.5f;
    emitterData.Time = 0.0f;
    emitterData.GridSize = static_cast<uint32_t>(std::sqrt(static_cast<float>(grassCount)));
    emitterData.Lod0BladeCount = std::max(1u, std::min(lod0BladeCount, kMaxBladeCount));
    emitterData.Lod1BladeCount = std::max(1u, std::min(lod1BladeCount, kMaxBladeCount));
    emitterData.AtlasTextureCount = 1;

    // ������� �������� ������� � 3 �����������
    primeGrassEmitter = std::make_shared<GrassEmitter>(
        primeDevice, grassCount, worldSize, emitterData.Lod0BladeCount, emitterData.Lod1BladeCount);

    InitPSO(secondDevice);
    CreateBuffers();
    DescriptorInitialize();
    GenerateGrassDataCPU();
}

CrossAdapterGrassEmitter::~CrossAdapterGrassEmitter()
{
}

void CrossAdapterGrassEmitter::InitPSO(const std::shared_ptr<GDevice>& otherDevice)
{
    CD3DX12_DESCRIPTOR_RANGE uavRange;
    uavRange.Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 0);

    computeRS = std::make_shared<GRootSignature>();
    computeRS->AddConstantBufferParameter(0);
    computeRS->AddDescriptorParameter(&uavRange, 1);
    computeRS->Initialize(otherDevice);

    auto generateShader = std::make_shared<GShader>(L"Shaders\\ComputeGrass.hlsl", ComputeShader, nullptr, "CS", "cs_5_1");
    generateShader->LoadAndCompile();

    generatePSO = std::make_shared<ComputePSO>();
    generatePSO->SetRootSignature(*computeRS.get());
    generatePSO->SetShader(generateShader.get());
    generatePSO->Initialize(secondDevice);

    CD3DX12_DESCRIPTOR_RANGE expandInputRange;
    expandInputRange.Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 0);
    CD3DX12_DESCRIPTOR_RANGE expandOutputRanges[2];
    expandOutputRanges[0].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 0);
    expandOutputRanges[1].Init(D3D12_DESCRIPTOR_RANGE_TYPE_UAV, 1, 1);

    expandRS = std::make_shared<GRootSignature>();
    expandRS->AddConstantBufferParameter(0);
    expandRS->AddConstantBufferParameter(1);
    expandRS->AddDescriptorParameter(&expandInputRange, 1);
    expandRS->AddDescriptorParameter(&expandOutputRanges[0], 1);
    expandRS->AddDescriptorParameter(&expandOutputRanges[1], 1);
    expandRS->Initialize(otherDevice);

    auto expandShader = std::make_shared<GShader>(L"Shaders\\ComputeGrass.hlsl", ComputeShader, nullptr, "CS_ExpandGrassToVertices", "cs_5_1");
    expandShader->LoadAndCompile();

    expandPSO = std::make_shared<ComputePSO>();
    expandPSO->SetRootSignature(*expandRS.get());
    expandPSO->SetShader(expandShader.get());
    expandPSO->Initialize(secondDevice);

    CD3DX12_DESCRIPTOR_RANGE textureRange;
    textureRange.Init(D3D12_DESCRIPTOR_RANGE_TYPE_SRV, 1, 1);
    drawRS = std::make_shared<GRootSignature>();
    drawRS->AddConstantBufferParameter(0);
    drawRS->AddConstantBufferParameter(1);
    drawRS->AddShaderResourceView(8);
    drawRS->AddShaderResourceView(9);
    drawRS->AddDescriptorParameter(&textureRange, 1);
    CD3DX12_STATIC_SAMPLER_DESC sampler(
        0,
        D3D12_FILTER_MIN_MAG_MIP_LINEAR,
        D3D12_TEXTURE_ADDRESS_MODE_WRAP,
        D3D12_TEXTURE_ADDRESS_MODE_WRAP,
        D3D12_TEXTURE_ADDRESS_MODE_WRAP);
    drawRS->AddStaticSampler(sampler);
    drawRS->Initialize(primeDevice);

    auto expandedVS = std::make_shared<GShader>(L"Shaders\\GrassDraw.hlsl", VertexShader, nullptr, "VS_Expanded", "vs_5_1");
    expandedVS->LoadAndCompile();
    auto expandedPS = std::make_shared<GShader>(L"Shaders\\GrassDraw.hlsl", PixelShader, nullptr, "PS_Expanded", "ps_5_1");
    expandedPS->LoadAndCompile();

    D3D12_GRAPHICS_PIPELINE_STATE_DESC psoDesc = {};
    psoDesc.InputLayout = { nullptr, 0 };
    psoDesc.pRootSignature = drawRS->GetNativeSignature().Get();
    psoDesc.VS = expandedVS->GetShaderResource();
    psoDesc.PS = expandedPS->GetShaderResource();
    psoDesc.RasterizerState = CD3DX12_RASTERIZER_DESC(D3D12_DEFAULT);
    psoDesc.RasterizerState.CullMode = D3D12_CULL_MODE_NONE;
    psoDesc.BlendState = CD3DX12_BLEND_DESC(D3D12_DEFAULT);
    D3D12_RENDER_TARGET_BLEND_DESC blendDesc = {};
    blendDesc.BlendEnable = true;
    blendDesc.LogicOpEnable = false;
    blendDesc.SrcBlend = D3D12_BLEND_SRC_ALPHA;
    blendDesc.DestBlend = D3D12_BLEND_INV_SRC_ALPHA;
    blendDesc.SrcBlendAlpha = D3D12_BLEND_ZERO;
    blendDesc.DestBlendAlpha = D3D12_BLEND_ONE;
    blendDesc.BlendOp = D3D12_BLEND_OP_ADD;
    blendDesc.BlendOpAlpha = D3D12_BLEND_OP_ADD;
    blendDesc.LogicOp = D3D12_LOGIC_OP_NOOP;
    blendDesc.RenderTargetWriteMask = D3D12_COLOR_WRITE_ENABLE_ALL;
    psoDesc.BlendState.RenderTarget[0] = blendDesc;
    psoDesc.DepthStencilState = CD3DX12_DEPTH_STENCIL_DESC(D3D12_DEFAULT);
    psoDesc.DepthStencilState.DepthFunc = D3D12_COMPARISON_FUNC_LESS_EQUAL;
    psoDesc.SampleMask = UINT_MAX;
    psoDesc.PrimitiveTopologyType = D3D12_PRIMITIVE_TOPOLOGY_TYPE_TRIANGLE;
    psoDesc.NumRenderTargets = 1;
    psoDesc.RTVFormats[0] = GetSRGBFormat(BackBufferFormat);
    psoDesc.DSVFormat = DepthStencilFormat;
    psoDesc.SampleDesc.Count = 1;
    psoDesc.SampleDesc.Quality = 0;

    expandedDrawPSO = std::make_shared<GraphicPSO>(RenderMode::Transparent);
    expandedDrawPSO->SetPsoDesc(psoDesc);
    expandedDrawPSO->Initialize(primeDevice);
}

void CrossAdapterGrassEmitter::CreateBuffers()
{
    if (grassBuffer)
    {
        grassBuffer->Reset();
        grassBuffer.reset();
    }

    if (crossAdapterGrassBuffer)
    {
        crossAdapterGrassBuffer->Reset();
        crossAdapterGrassBuffer.reset();
    }
    if (expandedVertexBuffer)
    {
        expandedVertexBuffer->Reset();
        expandedVertexBuffer.reset();
    }
    if (crossAdapterExpandedVertexBuffer)
    {
        crossAdapterExpandedVertexBuffer->Reset();
        crossAdapterExpandedVertexBuffer.reset();
    }
    if (primeExpandedVertexBuffer)
    {
        primeExpandedVertexBuffer->Reset();
        primeExpandedVertexBuffer.reset();
    }
    if (visibleVertexCountBuffer)
    {
        visibleVertexCountBuffer->Reset();
        visibleVertexCountBuffer.reset();
    }
    if (crossAdapterVisibleVertexCountBuffer)
    {
        crossAdapterVisibleVertexCountBuffer->Reset();
        crossAdapterVisibleVertexCountBuffer.reset();
    }
    if (primeVisibleVertexCountBuffer)
    {
        primeVisibleVertexCountBuffer->Reset();
        primeVisibleVertexCountBuffer.reset();
    }

    grassBuffer = std::make_shared<GBuffer>(
        secondDevice,
        sizeof(GrassData),
        emitterData.GrassCount,
        L"Second Grass Buffer",
        D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS
    );

    auto desc = grassBuffer->GetD3D12ResourceDesc();
    crossAdapterGrassBuffer = std::make_shared<GCrossAdapterResource>(
        desc, primeDevice, secondDevice, L"Cross Adapter Grass Buffer");

    expandedVertexBuffer = std::make_shared<GBuffer>(
        secondDevice,
        sizeof(GrassRenderVertex),
        emitterData.GrassCount * kMaxVerticesPerBlade,
        L"Second Expanded Grass Vertex Buffer",
        D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
    desc = expandedVertexBuffer->GetD3D12ResourceDesc();
    crossAdapterExpandedVertexBuffer = std::make_shared<GCrossAdapterResource>(
        desc, primeDevice, secondDevice, L"Cross Adapter Expanded Grass Vertex Buffer");
    primeExpandedVertexBuffer = std::make_shared<GBuffer>(
        primeDevice,
        sizeof(GrassRenderVertex),
        emitterData.GrassCount * kMaxVerticesPerBlade,
        L"Prime Expanded Grass Vertex Buffer",
        D3D12_RESOURCE_FLAG_NONE);
    visibleVertexCountBuffer = std::make_shared<GBuffer>(
        secondDevice,
        sizeof(uint32_t),
        1,
        L"Second Visible Grass Vertex Count",
        D3D12_RESOURCE_FLAG_ALLOW_UNORDERED_ACCESS);
    desc = visibleVertexCountBuffer->GetD3D12ResourceDesc();
    crossAdapterVisibleVertexCountBuffer = std::make_shared<GCrossAdapterResource>(
        desc, primeDevice, secondDevice, L"Cross Adapter Visible Grass Vertex Count");
    primeVisibleVertexCountBuffer = std::make_shared<GBuffer>(
        primeDevice,
        sizeof(uint32_t),
        1,
        L"Prime Visible Grass Vertex Count",
        D3D12_RESOURCE_FLAG_NONE);

    grassDataCPU.resize(emitterData.GrassCount);
}

void CrossAdapterGrassEmitter::DescriptorInitialize()
{
    computeDescriptors = secondDevice->AllocateDescriptors(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, 1);
    expandDescriptors = secondDevice->AllocateDescriptors(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, 3);

    D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};
    uavDesc.Format = DXGI_FORMAT_UNKNOWN;
    uavDesc.ViewDimension = D3D12_UAV_DIMENSION_BUFFER;
    uavDesc.Buffer.FirstElement = 0;
    uavDesc.Buffer.NumElements = emitterData.GrassCount;
    uavDesc.Buffer.StructureByteStride = sizeof(GrassData);
    uavDesc.Buffer.Flags = D3D12_BUFFER_UAV_FLAG_NONE;

    grassBuffer->CreateUnorderedAccessView(&uavDesc, &computeDescriptors, 0);

    D3D12_SHADER_RESOURCE_VIEW_DESC srvDesc = {};
    srvDesc.Format = DXGI_FORMAT_UNKNOWN;
    srvDesc.Shader4ComponentMapping = D3D12_DEFAULT_SHADER_4_COMPONENT_MAPPING;
    srvDesc.ViewDimension = D3D12_SRV_DIMENSION_BUFFER;
    srvDesc.Buffer.FirstElement = 0;
    srvDesc.Buffer.NumElements = emitterData.GrassCount;
    srvDesc.Buffer.StructureByteStride = sizeof(GrassData);
    srvDesc.Buffer.Flags = D3D12_BUFFER_SRV_FLAG_NONE;
    grassBuffer->CreateShaderResourceView(&srvDesc, &expandDescriptors, 0);

    D3D12_UNORDERED_ACCESS_VIEW_DESC expandedUavDesc = {};
    expandedUavDesc.Format = DXGI_FORMAT_UNKNOWN;
    expandedUavDesc.ViewDimension = D3D12_UAV_DIMENSION_BUFFER;
    expandedUavDesc.Buffer.FirstElement = 0;
    expandedUavDesc.Buffer.NumElements = emitterData.GrassCount * kMaxVerticesPerBlade;
    expandedUavDesc.Buffer.StructureByteStride = sizeof(GrassRenderVertex);
    expandedUavDesc.Buffer.Flags = D3D12_BUFFER_UAV_FLAG_NONE;
    expandedVertexBuffer->CreateUnorderedAccessView(&expandedUavDesc, &expandDescriptors, 1);

    D3D12_UNORDERED_ACCESS_VIEW_DESC counterUavDesc = {};
    counterUavDesc.Format = DXGI_FORMAT_R32_UINT;
    counterUavDesc.ViewDimension = D3D12_UAV_DIMENSION_BUFFER;
    counterUavDesc.Buffer.FirstElement = 0;
    counterUavDesc.Buffer.NumElements = 1;
    counterUavDesc.Buffer.StructureByteStride = 0;
    counterUavDesc.Buffer.Flags = D3D12_BUFFER_UAV_FLAG_NONE;
    visibleVertexCountBuffer->CreateUnorderedAccessView(&counterUavDesc, &expandDescriptors, 2);
}

void CrossAdapterGrassEmitter::GenerateGrassDataCPU()
{
    float cellSize = emitterData.WorldSize / static_cast<float>(emitterData.GridSize);
    float halfWorld = emitterData.WorldSize * 0.5f;

    for (uint32_t i = 0; i < emitterData.GrassCount; ++i)
    {
        uint32_t x = i % emitterData.GridSize;
        uint32_t z = i / emitterData.GridSize;

        if (z >= emitterData.GridSize) break;

        float posX = (static_cast<float>(x) + 0.5f) * cellSize - halfWorld;
        float posZ = (static_cast<float>(z) + 0.5f) * cellSize - halfWorld;

        posX += MathHelper::RandF(-cellSize * 0.4f, cellSize * 0.4f);
        posZ += MathHelper::RandF(-cellSize * 0.4f, cellSize * 0.4f);

        GrassData& grass = grassDataCPU[i];
        grass.Position = Vector3(posX, 0.0f, posZ);
        grass.Scale = MathHelper::RandF(0.8f, 1.5f);
        grass.Rotation = MathHelper::RandF(0.0f, DirectX::XM_2PI);
        grass.WindOffset = MathHelper::RandF(0.0f, DirectX::XM_2PI);
        grass.TextureIndex = 0;
        grass.Padding[0] = grass.Padding[1] = grass.Padding[2] = 0;
    }
}

void CrossAdapterGrassEmitter::Update()
{
    emitterData.Time += 0.016f;

    // ������������� gameObject ��� ��������� ��������
    if (primeGrassEmitter && gameObject)
    {
        primeGrassEmitter->gameObject = gameObject;
        cullData.World = gameObject->GetTransform()->GetWorldMatrix().Transpose();
    }

    // ��������� ��������� ��������� ��������
    primeGrassEmitter->UpdateConstants(emitterData);
    primeGrassEmitter->Update();
    
    if (needRegenerate && !useSharedCompute)
    {
        GenerateGrassDataCPU();

        auto queue = primeDevice->GetCommandQueue(GQueueType::Compute);
        auto cmdList = queue->GetCommandList();

        primeGrassEmitter->GetGrassBuffer()->LoadData(grassDataCPU.data(), cmdList);

        cmdList->TransitionBarrier(primeGrassEmitter->GetGrassBuffer()->GetD3D12Resource(),
            D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        cmdList->FlushResourceBarriers();

        queue->ExecuteCommandList(cmdList);
        queue->Flush();

        needRegenerate = false;
    }
}

void CrossAdapterGrassEmitter::Draw(const std::shared_ptr<GCommandList>& cmdList)
{
    if (useSharedCompute)
    {
        cmdList->CopyResource(primeExpandedVertexBuffer->GetD3D12Resource(),
            crossAdapterExpandedVertexBuffer->GetPrimeResource().GetD3D12Resource());
        cmdList->CopyResource(primeVisibleVertexCountBuffer->GetD3D12Resource(),
            crossAdapterVisibleVertexCountBuffer->GetPrimeResource().GetD3D12Resource());

        cmdList->TransitionBarrier(primeExpandedVertexBuffer->GetD3D12Resource(), D3D12_RESOURCE_STATE_NON_PIXEL_SHADER_RESOURCE);
        cmdList->FlushResourceBarriers();

        const auto worldCB = primeGrassEmitter->GetWorldConstantsBuffer();
        const auto objectCB = primeGrassEmitter->GetObjectPositionBuffer();
        const auto descriptors = primeGrassEmitter->GetGrassDescriptors();
        if (worldCB && objectCB && descriptors)
        {
            cmdList->SetPipelineState(*expandedDrawPSO.get());
            cmdList->SetRootSignature(*drawRS);
            cmdList->SetDescriptorsHeap(descriptors);
            cmdList->SetRootConstantBufferView(0, *objectCB);
            cmdList->SetRootConstantBufferView(1, *worldCB);
            cmdList->SetRootShaderResourceView(2, *primeExpandedVertexBuffer);
            cmdList->SetRootShaderResourceView(3, *primeVisibleVertexCountBuffer);
            cmdList->SetRootDescriptorTable(4, descriptors, 1);
            cmdList->SetPrimitiveTopology(D3D_PRIMITIVE_TOPOLOGY_TRIANGLELIST);
            cmdList->Draw(emitterData.GrassCount * kMaxVerticesPerBlade, 1, 0, 0);
        }
    }
    else
    {
        primeGrassEmitter->Draw(cmdList);
    }
}

void CrossAdapterGrassEmitter::Dispatch(const std::shared_ptr<GCommandList>& cmdList)
{
    if (dirtyActivated == Enable)
    {
        if (needRegenerate)
        {
            cmdList->CopyResource(grassBuffer->GetD3D12Resource(),
                crossAdapterGrassBuffer->GetSharedResource().GetD3D12Resource());
        }
        dirtyActivated = None;
    }

    if (dirtyActivated == Disable)
    {
        // Single-GPU path regenerates/uploads grass on prime in Update().
        // Do not overwrite it with cross-adapter shadow resources here.
        dirtyActivated = None;
    }

    if (useSharedCompute)
    {
        auto constantBuffer = std::make_shared<GBuffer>(secondDevice, sizeof(GrassEmitterData), 1, L"Grass Emitter Constant");
        constantBuffer->LoadData(&emitterData, cmdList);
        auto cullBuffer = std::make_shared<GBuffer>(secondDevice, sizeof(GrassCullData), 1, L"Grass Cull Constant");
        cullBuffer->LoadData(&cullData, cmdList);

        uint32_t threadGroups = (emitterData.GrassCount + 63) / 64;

        if (needRegenerate)
        {
            cmdList->TransitionBarrier(grassBuffer->GetD3D12Resource(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
            cmdList->FlushResourceBarriers();

            cmdList->SetPipelineState(*generatePSO.get());
            cmdList->SetRootSignature(*computeRS);

            cmdList->SetDescriptorsHeap(&computeDescriptors);

            cmdList->SetRootConstantBufferView(0, *constantBuffer);
            cmdList->SetRootDescriptorTable(1, &computeDescriptors, 0);
            cmdList->Dispatch(threadGroups, 1, 1);

            cmdList->UAVBarrier(grassBuffer->GetD3D12Resource());
            cmdList->FlushResourceBarriers();
        }

        cmdList->SetPipelineState(*expandPSO.get());
        cmdList->SetRootSignature(*expandRS);
        cmdList->SetDescriptorsHeap(&expandDescriptors);
        uint32_t zeroCounter = 0;
        visibleVertexCountBuffer->LoadData(&zeroCounter, cmdList);
        cmdList->SetRootConstantBufferView(0, *constantBuffer);
        cmdList->SetRootConstantBufferView(1, *cullBuffer);
        cmdList->SetRootDescriptorTable(2, &expandDescriptors, 0);
        cmdList->SetRootDescriptorTable(3, &expandDescriptors, 1);
        cmdList->SetRootDescriptorTable(4, &expandDescriptors, 2);
        cmdList->Dispatch(threadGroups, 1, 1);

        cmdList->UAVBarrier(expandedVertexBuffer->GetD3D12Resource());
        cmdList->FlushResourceBarriers();

        cmdList->CopyResource(crossAdapterExpandedVertexBuffer->GetSharedResource().GetD3D12Resource(),
            expandedVertexBuffer->GetD3D12Resource());
        cmdList->CopyResource(crossAdapterVisibleVertexCountBuffer->GetSharedResource().GetD3D12Resource(),
            visibleVertexCountBuffer->GetD3D12Resource());

        needRegenerate = false;
    }
}

void CrossAdapterGrassEmitter::SetWindStrength(float strength)
{
    emitterData.WindStrength = strength;
}

void CrossAdapterGrassEmitter::SetWorldSize(float size)
{
    emitterData.WorldSize = size;
    needRegenerate = true;
}

void CrossAdapterGrassEmitter::SetGrassCount(uint32_t count)
{
    if (count == 0)
    {
        count = 1;
    }
    if (emitterData.GrassCount == count)
    {
        return;
    }

    emitterData.GrassCount = count;
    emitterData.GridSize = static_cast<uint32_t>(std::sqrt(static_cast<float>(count)));
    primeGrassEmitter->SetGrassCount(count);
    CreateBuffers();
    DescriptorInitialize();
    GenerateGrassDataCPU();
    needRegenerate = true;
}

void CrossAdapterGrassEmitter::SetLodBladeCounts(uint32_t lod0BladeCount, uint32_t lod1BladeCount)
{
    emitterData.Lod0BladeCount = std::max(1u, std::min(lod0BladeCount, kMaxBladeCount));
    emitterData.Lod1BladeCount = std::max(1u, std::min(lod1BladeCount, kMaxBladeCount));
    if (primeGrassEmitter)
    {
        primeGrassEmitter->SetLodBladeCounts(emitterData.Lod0BladeCount, emitterData.Lod1BladeCount);
    }
}

void CrossAdapterGrassEmitter::Regenerate()
{
    needRegenerate = true;
}

void CrossAdapterGrassEmitter::EnableShared()
{
    useSharedCompute = true;
    dirtyActivated = Enable;
    needRegenerate = true;
}

void CrossAdapterGrassEmitter::DisableShared()
{
    useSharedCompute = false;
    dirtyActivated = Disable;
    // Prime grass buffer was only filled on GPU2 when shared; force CPU upload next Update.
    needRegenerate = true;
}

void CrossAdapterGrassEmitter::SetWorldConstantsBuffer(const GBuffer* worldConstants)
{
    if (primeGrassEmitter)
    {
        primeGrassEmitter->SetWorldConstantsBuffer(worldConstants);
    }
}

void CrossAdapterGrassEmitter::SetFrustumCullingData(const Matrix& viewProj, const Vector3& eyePos, const float maxDistance,
                                                     const float lod0Distance, const uint32_t lod0BaseSegments,
                                                     const float windTessellationScale)
{
    cullData.ViewProj = viewProj;
    cullData.EyePos = eyePos;
    cullData.MaxDistance = maxDistance;
    cullData.Lod0Distance = lod0Distance;
    cullData.Lod0BaseSegments = std::min(lod0BaseSegments, kMaxLod0Segments);
    cullData.WindTessellationScale = windTessellationScale;
}