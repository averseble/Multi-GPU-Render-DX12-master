#pragma once
#include "GDescriptor.h"
#include "Renderer.h"
#include "GrassData.h"

class GrassEmitter : public Renderer
{
public:
    GrassEmitter(std::shared_ptr<GDevice> device, uint32_t grassCount = 10000, float worldSize = 100.0f);
    virtual ~GrassEmitter();

    // Renderer interface
    void Update() override;
    void Draw(const std::shared_ptr<GCommandList>& cmdList) override;
    void Dispatch(const std::shared_ptr<GCommandList>& cmdList); // Для генерации на GPU

    // Управление
    void SetWindStrength(float strength) { emitterData.WindStrength = strength; }
    void SetWorldSize(float size) { emitterData.WorldSize = size; needRegenerate = true; }
    void SetGrassCount(uint32_t count) { emitterData.GrassCount = count; needRegenerate = true; }
    void Regenerate();

    std::shared_ptr<GBuffer> GetGrassBuffer() const { return grassBuffer; }
    void UpdateConstants(const GrassEmitterData& data) { emitterData = data; }

private:
    void Initialize();
    void CreateBuffers();
    void CreateRootSignatures();
    void CreatePipelineState();
    void CreateComputeShaders();
    void DescriptorInitialize();
    void GenerateGrassDataCPU(); 

    std::shared_ptr<GDevice> device;

    // Буферы
    std::shared_ptr<ConstantUploadBuffer<ObjectConstants>> objectPositionBuffer;
    std::shared_ptr<GBuffer> grassBuffer;                 // RWStructuredBuffer<GrassData>
    std::shared_ptr<GBuffer> constantBuffer;              // ConstantBuffer<GrassEmitterData>

    // Дескрипторы
    GDescriptor grassDescriptors;                          // Для рендера (SRV)
    GDescriptor computeDescriptors;                        // Для compute (UAV) - опционально

    // Данные
    std::vector<GrassData> grassDataCPU;                   // CPU копия
    GrassEmitterData emitterData = {};
    ObjectConstants objectWorldData{};

    // Текстуры
    std::vector<std::shared_ptr<GTexture>> Atlas;         // Текстуры травы

    // Шейдеры и PSO
    std::shared_ptr<GRootSignature> renderSignature;
    std::shared_ptr<GRootSignature> computeSignature;     // Для генерации на GPU
    std::shared_ptr<GraphicPSO> renderPSO;
    std::shared_ptr<ComputePSO> generatePSO;              // Для генерации на GPU
    std::shared_ptr<GShader> generateShader;              // Compute шейдер для генерации

    // Состояние
    bool needRegenerate = true;
    bool useGPUGeneration = false;                          // true если используем compute shader
};