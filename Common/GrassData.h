#pragma once
#include "MathHelper.h"

using namespace DirectX::SimpleMath;

struct GrassData
{
    Vector3 Position;
    float Scale;
    float Rotation;
    float WindOffset;
    uint32_t TextureIndex;
    uint32_t Padding[3]; // ��� ������������ �� 16 ����
};

struct GrassRenderVertex
{
    Vector3 Position;
    float Padding0 = 0.0f;
    Vector2 TexCoord;
    Vector2 Padding1 = Vector2::Zero;
};

// ��������� �������� �����
struct GrassEmitterData
{
    static constexpr uint32_t MaxWindOrigins = 4;
    // ������ ��, ��� ������� ������������
    uint32_t GrassCount;           // ���������� ��������
    uint32_t GridSize;             // ������ �����
    float WorldSize;                // ������ ����
    float QuadSize;                 // ������ �����
    float Time;                     // ����� ��� ��������
    float WindStrength;             // ���� �����
    float WindIntensity = 1.0f;
    float WindAmplitude = 1.0f;
    float Lod0BladeWidthScale = 1.0f;
    float Lod0BladeHeightScale = 1.0f;
    float Lod1BladeWidthScale = 1.0f;
    float Lod1BladeHeightScale = 1.0f;
    float Lod0SdofNaturalFreq = 2.5f;
    float Lod0SdofDampingRatio = 0.35f;
    float Lod0DistanceThreshold = 300.0f;
    float Lod1DistanceThreshold = 900.0f;
    uint32_t AtlasTextureCount;      // ���������� �������
    uint32_t GpuStressIterations = 0;
    uint32_t Lod0BladeCount = 3;
    uint32_t Lod1BladeCount = 1;
    Vector2 WindDirection = Vector2(1.0f, 0.0f);
    uint32_t WindOriginCount = 1;
    float WindMapFalloff = 1.5f;
    float FieldInfluenceScale = 1.0f;
    float DebugNearestOriginTint = 0.0f;
    float Padding[2];                // ������������ �� 16-������� �������
    Vector4 WindOriginData[MaxWindOrigins] =
    {
        Vector4(0.0f, 0.0f, 0.0f, 1200.0f),
        Vector4(0.0f, 0.0f, 0.0f, 1200.0f),
        Vector4(0.0f, 0.0f, 0.0f, 1200.0f),
        Vector4(0.0f, 0.0f, 0.0f, 1200.0f)
    };
    Vector4 WindDirectionData[MaxWindOrigins] =
    {
        Vector4(1.0f, 0.0f, 0.0f, 1.0f),
        Vector4(1.0f, 0.0f, 0.0f, 1.0f),
        Vector4(1.0f, 0.0f, 0.0f, 1.0f),
        Vector4(1.0f, 0.0f, 0.0f, 1.0f)
    };
};

struct GrassCullData
{
    Matrix World = Matrix::Identity;
    Matrix ViewProj = Matrix::Identity;
    Vector3 EyePos = Vector3::Zero;
    float MaxDistance = 1500.0f;
    float Lod0Distance = 300.0f;
    float Lod1Distance = 900.0f;
    uint32_t Lod0BaseSegments = 4;
    float WindTessellationScale = 4.0f;
    float Padding0 = 0.0f;
};