#pragma once
#include "GDescriptor.h"
#include "Renderer.h"
#include "GrassData.h"

class GrassEmitter : public Renderer
{
public:
    GrassEmitter(std::shared_ptr<GDevice> device, uint32_t grassCount = 10000, float worldSize = 100.0f,
                 uint32_t lod0BladeCount = 3, uint32_t lod1BladeCount = 1);
    virtual ~GrassEmitter();

    // Renderer interface
    void Update() override;
    void Draw(const std::shared_ptr<GCommandList>& cmdList) override;
    void Dispatch(const std::shared_ptr<GCommandList>& cmdList); // ˜˜˜ ˜˜˜˜˜˜˜˜˜ ˜˜ GPU

    // ˜˜˜˜˜˜˜˜˜˜
    void SetWindStrength(float strength) { emitterData.WindStrength = strength; }
    void SetWorldSize(float size) { emitterData.WorldSize = size; needRegenerate = true; }
    void SetGrassCount(uint32_t count);
    void SetLodBladeCounts(uint32_t lod0BladeCount, uint32_t lod1BladeCount);
    void Regenerate();

    std::shared_ptr<GBuffer> GetGrassBuffer() const { return grassBuffer; }
    void UpdateConstants(const GrassEmitterData& data) { emitterData = data; }
    void SetWorldConstantsBuffer(const GBuffer* worldConstants) { worldConstantsBuffer = worldConstants; }
    const GBuffer* GetWorldConstantsBuffer() const { return worldConstantsBuffer; }
    const GDescriptor* GetGrassDescriptors() const { return &grassDescriptors; }
    const GBuffer* GetObjectPositionBuffer() const { return objectPositionBuffer.get(); }

private:
    void Initialize();
    void CreateBuffers();
    void CreateRootSignatures();
    void CreatePipelineState();
    void CreateComputeShaders();
    void DescriptorInitialize();
    void GenerateGrassDataCPU(); 

    std::shared_ptr<GDevice> device;

    // ˜˜˜˜˜˜
    std::shared_ptr<ConstantUploadBuffer<ObjectConstants>> objectPositionBuffer;
    std::shared_ptr<GBuffer> grassBuffer;                 // RWStructuredBuffer<GrassData>
    std::shared_ptr<GBuffer> constantBuffer;              // ConstantBuffer<GrassEmitterData>
    const GBuffer* worldConstantsBuffer = nullptr;        // b1 WorldConstants for grass draw

    // ˜˜˜˜˜˜˜˜˜˜˜
    GDescriptor grassDescriptors;                          // ˜˜˜ ˜˜˜˜˜˜˜ (SRV)
    GDescriptor computeDescriptors;                        // ˜˜˜ compute (UAV) - ˜˜˜˜˜˜˜˜˜˜˜

    // ˜˜˜˜˜˜
    std::vector<GrassData> grassDataCPU;                   // CPU ˜˜˜˜˜
    GrassEmitterData emitterData = {};
    ObjectConstants objectWorldData{};

    // ˜˜˜˜˜˜˜˜
    std::vector<std::shared_ptr<GTexture>> Atlas;         // ˜˜˜˜˜˜˜˜ ˜˜˜˜˜

    // ˜˜˜˜˜˜˜ ˜ PSO
    std::shared_ptr<GRootSignature> renderSignature;
    std::shared_ptr<GRootSignature> computeSignature;     // ˜˜˜ ˜˜˜˜˜˜˜˜˜ ˜˜ GPU
    std::shared_ptr<GraphicPSO> renderPSO;
    std::shared_ptr<ComputePSO> generatePSO;              // ˜˜˜ ˜˜˜˜˜˜˜˜˜ ˜˜ GPU
    std::shared_ptr<GShader> generateShader;              // Compute ˜˜˜˜˜˜ ˜˜˜ ˜˜˜˜˜˜˜˜˜

    // ˜˜˜˜˜˜˜˜˜
    bool needRegenerate = true;
    bool useGPUGeneration = false;                          // true ˜˜˜˜ ˜˜˜˜˜˜˜˜˜˜ compute shader
};