#pragma once
#include "AssetsLoader.h"
#include "CrossAdapterParticleEmitter.h"
#include "ParticleEmitter.h"
#include "CrossAdapterGrassEmitter.h"
#include "GrassEmitter.h"
#include "d3dApp.h"
#include "Renderer.h"
#include "RenderModeFactory.h"
#include "ShadowMap.h"
#include "SSAA.h"
#include "SSAO.h"
#include "FrameResource.h"
#include "GCrossAdapterResource.h"
#include "GDeviceFactory.h"
#include "GDescriptor.h"
#include "Light.h"
#include <d3d12.h>
#include <array>
#include <string>
#include <limits>
#include <vector>

struct ImGui_ImplDX12_InitInfo;
class Transform;

class HybridParticleApp :
    public Common::D3DApp
{
public:
    HybridParticleApp(HINSTANCE hInstance);
    ~HybridParticleApp() override;

    bool Initialize() override;;

    int Run() override;
    void EnablePerformanceTestMode(int warmupSeconds = 5, int sampleSeconds = 20);
    void EnablePerformanceSweepMode(int warmupSeconds = 5, int sampleSeconds = 15);

protected:
    void Update(const GameTimer& gt) override;
    void PopulateShadowMapCommands(std::shared_ptr<GCommandList> cmdList);;
    void PopulateNormalMapCommands(const std::shared_ptr<GCommandList>& cmdList);
    void PopulateAmbientMapCommands(const std::shared_ptr<GCommandList>& cmdList);
    void PopulateForwardPathCommands(const std::shared_ptr<GCommandList>& cmdList);
   
    void PopulateDrawCommands(std::shared_ptr<GCommandList> cmdList,
                              RenderMode type);
    void PopulateInitRenderTarget(const std::shared_ptr<GCommandList>& cmdList, GTexture& renderTarget, GDescriptor* rtvMemory,
                                  UINT offsetRTV);
    void PopulateDrawFullQuadTexture(const std::shared_ptr<GCommandList>& cmdList,
                                     GDescriptor* renderTextureSRVMemory, UINT renderTextureMemoryOffset,
                                     GraphicPSO& pso);
    void Draw(const GameTimer& gt) override;

    void InitDevices();
    void InitFrameResource();
    void InitRootSignature();
    void InitPipeLineResource();
    void CreateMaterials();
    void InitSRVMemoryAndMaterials();
    void InitRenderPaths();
    void LoadStudyTexture();
    void LoadModels();
    void MipMasGenerate();
    void SortGO();
    void CreateGO();
    void CalculateFrameStats() override;
    void LogWriting();
    void WritePerformanceTestResults();
    void WritePerformanceSweepResults();
    void UpdateMaterials();
    void UpdateShadowTransform(const GameTimer& gt);
    void UpdateShadowPassCB(const GameTimer& gt);
    void UpdateMainPassCB(const GameTimer& gt);
    void UpdateSsaoCB(const GameTimer& gt);
    bool InitMainWindow() override;
    void OnResize() override;
    void Flush() override;
    LRESULT MsgProc(HWND hwnd, UINT msg, WPARAM wParam, LPARAM lParam) override;

    void InitImGui();
    void ShutdownImGui();
    void DrawImGui(const std::shared_ptr<GCommandList>& cmdList);

    std::shared_ptr<GDevice> primeDevice;
    std::shared_ptr<GDevice> secondDevice;

    LockThreadQueue<std::wstring> logQueue{};
    UINT64 primeGPURenderingTime = 0;
    UINT64 secondGPURenderingTime = 0;

    UINT64 primeGPUComputingTime = 0;
    UINT64 secondGPUComputingTime = 0;

    D3D12_VIEWPORT fullViewport{};
    D3D12_RECT fullRect;

    std::shared_ptr<AssetsLoader> assets;

    custom_unordered_map<std::wstring, std::shared_ptr<GModel>> models = MemoryAllocator::CreateUnorderedMap<
        std::wstring, std::shared_ptr<GModel>>();
    std::shared_ptr<GRootSignature> primeDeviceSignature;
    std::shared_ptr<GRootSignature> ssaoPrimeRootSignature;
    std::vector<D3D12_INPUT_ELEMENT_DESC> defaultInputLayout{};
    GDescriptor srvTexturesMemory;
    RenderModeFactory defaultPrimePipelineResources;


    bool IsStop = false;
    bool performanceTestMode = false;
    bool performanceSweepMode = false;
    int perfWarmupSeconds = 5;
    int perfSampleSeconds = 20;
    int perfCurrentStage = 0; // 0 = single GPU, 1 = multi GPU
    double perfStageStartTime = -1.0;
    bool perfStageInitialized = false;
    std::wstring perfResultPath;

    struct PerfAggregate
    {
        int samples = 0;
        double fpsSum = 0.0;
        double primeRenderSum = 0.0;
        double secondRenderSum = 0.0;
        double primeComputeSum = 0.0;
        double secondComputeSum = 0.0;
        double minFps = std::numeric_limits<double>::max();
        double maxFps = std::numeric_limits<double>::lowest();
    };
    std::array<PerfAggregate, 2> perfAggregates{};
    struct PerfScenario
    {
        std::wstring name;
        int grassCount = 5000;
        float lod0Distance = 350.0f;
        float lod1Distance = 1000.0f;
        int lod0BladeCount = 3;
        int lod1BladeCount = 1;
        float fieldInfluenceScale = 1.0f;
    };
    std::vector<PerfScenario> perfScenarios{};
    std::vector<std::array<PerfAggregate, 2>> perfScenarioAggregates{};

    const int StatisticStepSecondsCount = 120;


    std::shared_ptr<ShadowMap> shadowPath;
    std::shared_ptr<SSAO> ambientPrimePath;
    std::shared_ptr<SSAA> antiAliasingPrimePath;

    custom_vector<std::shared_ptr<GameObject>> gameObjects = MemoryAllocator::CreateVector<std::shared_ptr<
        GameObject>>();

    custom_vector<custom_vector<std::shared_ptr<Renderer>>> typedRenderer = MemoryAllocator::CreateVector<custom_vector<
        std::shared_ptr<Renderer>>>();

    bool UseCrossAdapter = true;
    bool UseCrossSync = false;


    custom_vector<CrossAdapterParticleEmitter*> crossEmitter = MemoryAllocator::CreateVector<CrossAdapterParticleEmitter*>();
    custom_vector<CrossAdapterGrassEmitter*> crossGrassEmitters = MemoryAllocator::CreateVector<CrossAdapterGrassEmitter*>();
    ComPtr<ID3D12Fence> primeComputeFence;
    ComPtr<ID3D12Fence> secondComputeFence;
    UINT64 sharedComputeFenceValue = 0;

    ComPtr<ID3D12Fence> primeRenderFence;
    ComPtr<ID3D12Fence> secondRenderFence;
    UINT64 sharedRenderFenceValue = 0;

    PassConstants mainPassCB;
    PassConstants shadowPassCB;
   // PassConstants shadowPassCB;

    custom_vector<std::shared_ptr<FrameResource>> frameResources = MemoryAllocator::CreateVector<std::shared_ptr<
        FrameResource>>();
    std::shared_ptr<FrameResource> currentFrameResource = nullptr;
    std::atomic<UINT> currentFrameResourceIndex = 0;

    custom_vector<Light*> lights = MemoryAllocator::CreateVector<Light*>();

    float mLightNearZ = 0.0f;
    float mLightFarZ = 0.0f;
    Vector3 mLightPosW;
    Matrix mLightView = Matrix::Identity;
    Matrix mLightProj = Matrix::Identity;
    Matrix mShadowTransform = Matrix::Identity;

    float mLightRotationAngle = 0.0f;
    Vector3 mBaseLightDirections[3] = {
        Vector3(0.57735f, -0.57735f, 0.57735f),
        Vector3(-0.57735f, -0.57735f, 0.57735f),
        Vector3(0.0f, -0.707f, -0.707f)
    };
    Vector3 mRotatedLightDirections[3];

    DirectX::BoundingSphere mSceneBounds;

    GDescriptor imguiSrvDescriptors;
    bool imguiInitialized = false;
    DXGI_ADAPTER_DESC3 primeAdapterDesc{};
    DXGI_ADAPTER_DESC3 secondAdapterDesc{};
    bool primeAdapterDescValid = false;
    bool secondAdapterDescValid = false;

    bool imguiFontDescriptorInUse = false;
    std::string imguiIniFilePath;
    float grassCullMaxDistance = 1800.0f;
    float grassLod0Distance = 350.0f;
    float grassLod1Distance = 1000.0f;
    int grassLod0BaseSegments = 4;
    int grassLod0BladeCount = 3;
    int grassLod1BladeCount = 1;
    float grassWindTessellationScale = 4.0f;
    float grassWindIntensity = 1.0f;
    float grassWindAmplitude = 1.0f;
    float grassLod0SdofNaturalFreq = 2.5f;
    float grassLod0SdofDampingRatio = 0.35f;
    float grassLod0BladeWidthScale = 1.0f;
    float grassLod0BladeHeightScale = 1.0f;
    float grassLod1BladeWidthScale = 1.0f;
    float grassLod1BladeHeightScale = 1.0f;
    Vector2 grassWindDirection = Vector2(1.0f, 0.0f);
    int grassWindOriginCount = 2;
    float grassWindMapFalloff = 1.5f;
    float grassFieldInfluenceScale = 1.0f;
    std::array<Vector4, 4> grassWindOrigins =
    {
        Vector4(-250.0f, 0.0f, -250.0f, 900.0f),
        Vector4( 350.0f, 0.0f,  120.0f, 900.0f),
        Vector4(   0.0f, 0.0f,    0.0f, 900.0f),
        Vector4(   0.0f, 0.0f,    0.0f, 900.0f)
    };
    std::array<Vector4, 4> grassWindDirections =
    {
        Vector4( 1.0f,  0.2f, 0.0f, 1.0f),
        Vector4(-0.6f,  1.0f, 0.0f, 1.0f),
        Vector4( 1.0f,  0.0f, 0.0f, 1.0f),
        Vector4( 1.0f,  0.0f, 0.0f, 1.0f)
    };
    bool showWindFieldDebug = false;
    bool debugNearestOriginTint = false;
    int windFieldGridResolution = 12;
    int grassBladeCount = 5000;
    float grassWorldSize = 200.0f;
    std::shared_ptr<Transform> grassFieldTransform = nullptr;
    std::shared_ptr<Transform> platformTransform = nullptr;
    int pendingGrassBladeCount = -1;
    bool fpsLimitEnabled = true;
    int fpsLimitTarget = 60;

    friend void HybridParticleApp_ImGuiSrvAllocFn(ImGui_ImplDX12_InitInfo* info,
                                                  D3D12_CPU_DESCRIPTOR_HANDLE* out_cpu_handle,
                                                  D3D12_GPU_DESCRIPTOR_HANDLE* out_gpu_handle);
    friend void HybridParticleApp_ImGuiSrvFreeFn(ImGui_ImplDX12_InitInfo* info,
                                                 D3D12_CPU_DESCRIPTOR_HANDLE cpu_handle,
                                                 D3D12_GPU_DESCRIPTOR_HANDLE gpu_handle);
};
