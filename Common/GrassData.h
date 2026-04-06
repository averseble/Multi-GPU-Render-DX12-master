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
    // ������ ��, ��� ������� ������������
    uint32_t GrassCount;           // ���������� ��������
    uint32_t GridSize;             // ������ �����
    float WorldSize;                // ������ ����
    float QuadSize;                 // ������ �����
    float Time;                     // ����� ��� ��������
    float WindStrength;             // ���� �����
    uint32_t AtlasTextureCount;      // ���������� �������
    uint32_t GpuStressIterations = 0;
    float Padding[2];                // ������������ �� 16-������� �������
};

struct GrassCullData
{
    Matrix World = Matrix::Identity;
    Matrix ViewProj = Matrix::Identity;
    Vector3 EyePos = Vector3::Zero;
    float MaxDistance = 1500.0f;
    float Lod0Distance = 300.0f;
    uint32_t Lod0BaseSegments = 4;
    float WindTessellationScale = 4.0f;
    float Padding0 = 0.0f;
};