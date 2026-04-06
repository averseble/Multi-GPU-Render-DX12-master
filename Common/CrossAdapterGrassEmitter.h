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
        float worldSize = 100.0f);
    virtual ~CrossAdapterGrassEmitter();

    void Update() override;
    void Draw(const std::shared_ptr<GCommandList>& cmdList) override;
    void Dispatch(const std::shared_ptr<GCommandList>& cmdList);

    void SetWindStrength(float strength);
    void SetWorldSize(float size);
    void SetGrassCount(uint32_t count);
    void Regenerate();

    void EnableShared();
    void DisableShared();
    void SetWorldConstantsBuffer(const GBuffer* worldConstants);
    void SetFrustumCullingData(const Matrix& viewProj, const Vector3& eyePos, float maxDistance = 1500.0f);


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
};