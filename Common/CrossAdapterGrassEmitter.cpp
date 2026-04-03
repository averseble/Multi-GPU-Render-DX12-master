#include "pch.h"
#include "CrossAdapterGrassEmitter.h"
#include "GCommandList.h"
#include "MathHelper.h"

CrossAdapterGrassEmitter::CrossAdapterGrassEmitter(std::shared_ptr<GDevice> primeDev,
    const std::shared_ptr<GDevice>& secondDev,
    uint32_t grassCount, float worldSize)
    : primeDevice(primeDev), secondDevice(secondDev)
{
    emitterData.GrassCount = grassCount;
    emitterData.WorldSize = worldSize;
    emitterData.QuadSize = 10.0f;
    emitterData.WindStrength = 0.5f;
    emitterData.Time = 0.0f;
    emitterData.GridSize = static_cast<uint32_t>(std::sqrt(static_cast<float>(grassCount)));
    emitterData.AtlasTextureCount = 1;

    // Создаем основной эмиттер с 3 параметрами
    primeGrassEmitter = std::make_shared<GrassEmitter>(primeDevice, grassCount, worldSize);

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

    grassDataCPU.resize(emitterData.GrassCount);
}

void CrossAdapterGrassEmitter::DescriptorInitialize()
{
    computeDescriptors = secondDevice->AllocateDescriptors(D3D12_DESCRIPTOR_HEAP_TYPE_CBV_SRV_UAV, 1);

    D3D12_UNORDERED_ACCESS_VIEW_DESC uavDesc = {};
    uavDesc.Format = DXGI_FORMAT_UNKNOWN;
    uavDesc.ViewDimension = D3D12_UAV_DIMENSION_BUFFER;
    uavDesc.Buffer.FirstElement = 0;
    uavDesc.Buffer.NumElements = emitterData.GrassCount;
    uavDesc.Buffer.StructureByteStride = sizeof(GrassData);
    uavDesc.Buffer.Flags = D3D12_BUFFER_UAV_FLAG_NONE;

    grassBuffer->CreateUnorderedAccessView(&uavDesc, &computeDescriptors, 0);
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

    // Устанавливаем gameObject для основного эмиттера
    if (primeGrassEmitter && gameObject)
    {
        primeGrassEmitter->gameObject = gameObject;
    }

    // Обновляем константы основного эмиттера
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
        cmdList->CopyResource(primeGrassEmitter->GetGrassBuffer()->GetD3D12Resource(),
            crossAdapterGrassBuffer->GetPrimeResource().GetD3D12Resource());
    }

    primeGrassEmitter->Draw(cmdList);
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
        cmdList->CopyResource(primeGrassEmitter->GetGrassBuffer()->GetD3D12Resource(),
            crossAdapterGrassBuffer->GetPrimeResource().GetD3D12Resource());
        dirtyActivated = None;
    }

    if (useSharedCompute && needRegenerate)
    {
        cmdList->TransitionBarrier(grassBuffer->GetD3D12Resource(), D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
        cmdList->FlushResourceBarriers();

        cmdList->SetPipelineState(*generatePSO.get());
        cmdList->SetRootSignature(*computeRS);

        cmdList->SetDescriptorsHeap(&computeDescriptors);

        auto constantBuffer = std::make_shared<GBuffer>(secondDevice, sizeof(GrassEmitterData), 1, L"Grass Emitter Constant");
        constantBuffer->LoadData(&emitterData, cmdList);
        cmdList->SetRootConstantBufferView(0, *constantBuffer);
        cmdList->SetRootDescriptorTable(1, &computeDescriptors, 0);

        uint32_t threadGroups = (emitterData.GrassCount + 63) / 64;
        cmdList->Dispatch(threadGroups, 1, 1);

        cmdList->UAVBarrier(grassBuffer->GetD3D12Resource());
        cmdList->FlushResourceBarriers();

        cmdList->CopyResource(crossAdapterGrassBuffer->GetSharedResource().GetD3D12Resource(),
            grassBuffer->GetD3D12Resource());

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
    emitterData.GrassCount = count;
    emitterData.GridSize = static_cast<uint32_t>(std::sqrt(static_cast<float>(count)));
    needRegenerate = true;
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
}