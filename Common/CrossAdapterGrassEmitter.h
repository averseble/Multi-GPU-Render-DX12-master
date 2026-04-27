#pragma once
#include "Renderer.h"
#include "GCrossAdapterResource.h"
#include "GDescriptor.h"
#include "GrassEmitter.h"

class CrossAdapterGrassEmitter : public Renderer
{
public:
    CrossAdapterGrassEmitter(std::shared_ptr<GDevice> primeDevice,
        const std::shared_ptr<GDevice>& secondDevice,
        uint32_t grassCount = 10000,
        float worldSize = 100.0f,
        uint32_t lod0BladeCount = 3,
        uint32_t lod1BladeCount = 1);
    virtual ~CrossAdapterGrassEmitter();

    void Update() override;
    void Draw(const std::shared_ptr<GCommandList>& cmdList) override;
    void Dispatch(const std::shared_ptr<GCommandList>& cmdList);

    void SetWindStrength(float strength);
    void SetWindIntensity(float intensity);
    void SetWindAmplitude(float amplitude);
    void SetLodBladeSize(float lod0WidthScale, float lod0HeightScale, float lod1WidthScale, float lod1HeightScale);
    void SetLod0Sdof(float naturalFreq, float dampingRatio);
    void SetWindGradient(uint32_t originCount, float falloff,
                         const Vector4* originData, const Vector4* directionData);
    void SetFieldInfluenceScale(float scale);
    void SetDebugNearestOriginTint(bool enabled);
    void SetWindDirection(const Vector2& direction);
    void SetWorldSize(float size);
    void SetGrassCount(uint32_t count);
    void SetLodBladeCounts(uint32_t lod0BladeCount, uint32_t lod1BladeCount);
    void Regenerate();

    void EnableShared();
    void DisableShared();
    void SetWorldConstantsBuffer(const GBuffer* worldConstants);
    void SetFrustumCullingData(const Matrix& viewProj, const Vector3& eyePos, float maxDistance = 1500.0f,
                               float lod0Distance = 300.0f, float lod1Distance = 900.0f,
                               uint32_t lod0BaseSegments = 4,
                               float windTessellationScale = 4.0f);


private:
    void InitPSO(const std::shared_ptr<GDevice>& otherDevice);
    void CreateBuffers();
    void DescriptorInitialize();
    void GenerateGrassDataCPU();

    std::shared_ptr<GDevice> primeDevice;
    std::shared_ptr<GDevice> secondDevice;

    std::shared_ptr<GrassEmitter> primeGrassEmitter;

    std::shared_ptr<GBuffer> grassBuffer;
    std::shared_ptr<GCrossAdapterResource> crossAdapterGrassBuffer;
    std::shared_ptr<GBuffer> expandedVertexBuffer;
    std::shared_ptr<GCrossAdapterResource> crossAdapterExpandedVertexBuffer;
    std::shared_ptr<GBuffer> primeExpandedVertexBuffer;
    std::shared_ptr<GBuffer> visibleVertexCountBuffer;
    std::shared_ptr<GCrossAdapterResource> crossAdapterVisibleVertexCountBuffer;
    std::shared_ptr<GBuffer> primeVisibleVertexCountBuffer;

    GDescriptor computeDescriptors;
    GDescriptor expandDescriptors;

    std::shared_ptr<ComputePSO> generatePSO;
    std::shared_ptr<ComputePSO> expandPSO;
    std::shared_ptr<GRootSignature> computeRS;
    std::shared_ptr<GRootSignature> expandRS;
    std::shared_ptr<GRootSignature> drawRS;
    std::shared_ptr<GraphicPSO> expandedDrawPSO;

    GrassEmitterData emitterData = {};
    GrassCullData cullData = {};
    std::vector<GrassData> grassDataCPU;

    bool useSharedCompute = false;
    bool needRegenerate = true;

    enum Status : short
    {
        None = -1,
        Enable = 0,
        Disable = 1
    };

    Status dirtyActivated = None;

    static constexpr uint32_t kMaxLod0Segments = 6;
    static constexpr uint32_t kMaxBladeCount = 4;
    static constexpr uint32_t kMaxVerticesPerBlade = kMaxBladeCount * kMaxLod0Segments * 6;
};