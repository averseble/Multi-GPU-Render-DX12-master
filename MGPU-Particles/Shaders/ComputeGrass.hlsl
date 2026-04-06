// ComputeGrass.hlsl
// Compute шейдер для генерации травы на GPU

struct GrassData
{
    float3 Position;
    float Scale;
    float Rotation;
    float WindOffset;
    uint TextureIndex;
    uint3 Padding3;
};

cbuffer GrassEmitterData : register(b0)
{
    uint GrassCount;
    uint GridSize;
    float WorldSize;
    float QuadSize;
    float Time;
    float WindStrength;
    uint AtlasTextureCount;
    uint GpuStressIterations;
    float2 Padding;
}

cbuffer GrassCullData : register(b1)
{
    float4x4 World;
    float4x4 ViewProj;
    float3 EyePos;
    float MaxDistance;
}

RWStructuredBuffer<GrassData> GrassBuffer : register(u0);
StructuredBuffer<GrassData> GrassInput : register(t0);

struct GrassRenderVertex
{
    float3 Position;
    float Padding0;
    float2 TexCoord;
    float2 Padding1;
};

RWStructuredBuffer<GrassRenderVertex> ExpandedGrassBuffer : register(u0);
RWStructuredBuffer<uint> VisibleVertexCounter : register(u1);

float Rand(float2 uv)
{
    return frac(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

float RandRange(float2 uv, float minVal, float maxVal)
{
    return lerp(minVal, maxVal, Rand(uv));
}

[numthreads(64, 1, 1)]
void CS(uint3 groupID : SV_GroupID, uint groupIndex : SV_GroupIndex, uint3 dispatchThreadID : SV_DispatchThreadID)
{
    uint grassIndex = dispatchThreadID.x;
    
    if (grassIndex >= GrassCount)
        return;
    
    uint x = grassIndex % GridSize;
    uint z = grassIndex / GridSize;
    
    float2 randomSeed = float2(grassIndex * 0.123, grassIndex * 0.456);
    
    GrassData grass;
    
    if (z >= GridSize)
    {
        // Для оставшихся элементов - случайные позиции
        grass.Position.x = RandRange(randomSeed, -WorldSize * 0.5f, WorldSize * 0.5f);
        grass.Position.y = 0.0f;
        grass.Position.z = RandRange(randomSeed + 1.0f, -WorldSize * 0.5f, WorldSize * 0.5f);
    }
    else
    {
        // Равномерное распределение по сетке
        float cellSize = WorldSize / float(GridSize);
        float halfWorld = WorldSize * 0.5f;
        
        float baseX = (float(x) + 0.5f) * cellSize - halfWorld;
        float baseZ = (float(z) + 0.5f) * cellSize - halfWorld;
        
        grass.Position.x = baseX + RandRange(randomSeed, -cellSize * 0.4f, cellSize * 0.4f);
        grass.Position.y = 0.0f;
        grass.Position.z = baseZ + RandRange(randomSeed + 1.0f, -cellSize * 0.4f, cellSize * 0.4f);
    }
    
    grass.Scale = RandRange(randomSeed + 2.0f, 0.8f, 1.5f);
    grass.Rotation = RandRange(randomSeed + 3.0f, 0.0f, 6.28318f);
    grass.WindOffset = RandRange(randomSeed + 4.0f, 0.0f, 6.28318f);
    grass.TextureIndex = 0;
    grass.Padding3 = uint3(0, 0, 0);
    
    GrassBuffer[grassIndex] = grass;
}

[numthreads(64, 1, 1)]
void CS_ExpandGrassToVertices(uint3 dispatchThreadID : SV_DispatchThreadID)
{
    uint grassIndex = dispatchThreadID.x;
    if (grassIndex >= GrassCount)
        return;

    GrassData grass = GrassInput[grassIndex];

    float width = QuadSize * grass.Scale * 0.5f;
    float height = QuadSize * grass.Scale;
    float cosR = cos(grass.Rotation);
    float sinR = sin(grass.Rotation);
    float wind = sin(Time * 2.0f + grass.WindOffset) * WindStrength;

    float3 local[4];
    local[0] = float3(-width, -height, 0.0f);
    local[1] = float3(-width,  height, 0.0f);
    local[2] = float3( width, -height, 0.0f);
    local[3] = float3( width,  height, 0.0f);

    local[1].x += wind * width * 2.0f;
    local[3].x += wind * width * 2.0f;

    float3 p[4];
    [unroll]
    for (uint i = 0; i < 4; ++i)
    {
        float3 o = local[i];
        p[i].x = o.x * cosR - o.z * sinR + grass.Position.x;
        p[i].z = o.x * sinR + o.z * cosR + grass.Position.z;
        p[i].y = o.y + grass.Position.y;
    }

    float4 worldCenter = mul(float4(grass.Position, 1.0f), World);
    float3 toEye = worldCenter.xyz - EyePos;
    if (dot(toEye, toEye) > (MaxDistance * MaxDistance))
    {
        return;
    }

    // Conservative frustum culling in clip/NDC space.
    float4 clipPos = mul(worldCenter, ViewProj);
    if (clipPos.w <= 1e-5f)
    {
        return;
    }

    float3 ndc = clipPos.xyz / clipPos.w;
    const float frustumMargin = 0.35f;
    if (ndc.x < -1.0f - frustumMargin || ndc.x > 1.0f + frustumMargin ||
        ndc.y < -1.0f - frustumMargin || ndc.y > 1.0f + frustumMargin ||
        ndc.z < -0.25f || ndc.z > 1.25f)
    {
        return;
    }

    uint baseVertex;
    InterlockedAdd(VisibleVertexCounter[0], 6u, baseVertex);
    GrassRenderVertex v;
    v.Padding0 = 0.0f;
    v.Padding1 = float2(0.0f, 0.0f);

    v.Position = p[0]; v.TexCoord = float2(0.0f, 1.0f); ExpandedGrassBuffer[baseVertex + 0] = v;
    v.Position = p[1]; v.TexCoord = float2(0.0f, 0.0f); ExpandedGrassBuffer[baseVertex + 1] = v;
    v.Position = p[2]; v.TexCoord = float2(1.0f, 1.0f); ExpandedGrassBuffer[baseVertex + 2] = v;
    v.Position = p[2]; v.TexCoord = float2(1.0f, 1.0f); ExpandedGrassBuffer[baseVertex + 3] = v;
    v.Position = p[1]; v.TexCoord = float2(0.0f, 0.0f); ExpandedGrassBuffer[baseVertex + 4] = v;
    v.Position = p[3]; v.TexCoord = float2(1.0f, 0.0f); ExpandedGrassBuffer[baseVertex + 5] = v;
}