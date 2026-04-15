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
    uint Lod0BladeCount;
    uint Lod1BladeCount;
    float2 Padding;
}

cbuffer GrassCullData : register(b1)
{
    float4x4 World;
    float4x4 ViewProj;
    float3 EyePos;
    float MaxDistance;
    float Lod0Distance;
    uint Lod0BaseSegments;
    float WindTessellationScale;
    float Padding0;
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

    float distToEye = length(toEye);
    bool useLod0 = distToEye <= Lod0Distance;
    uint segments = 1u;
    if (useLod0)
    {
        float windAbs = abs(wind);
        uint extraSeg = (uint)clamp(floor(windAbs * WindTessellationScale), 0.0f, 2.0f);
        segments = clamp(Lod0BaseSegments + extraSeg, 2u, 6u);
    }

    uint bladeCount = useLod0 ? clamp(Lod0BladeCount, 1u, 4u) : clamp(Lod1BladeCount, 1u, 4u);
    uint vertexCount = bladeCount * segments * 6u;
    uint baseVertex;
    InterlockedAdd(VisibleVertexCounter[0], vertexCount, baseVertex);
    GrassRenderVertex v;
    v.Padding0 = 0.0f;

    [loop]
    for (uint blade = 0u; blade < bladeCount; ++blade)
    {
        float bladeN = (bladeCount > 1u) ? (float(blade) / float(bladeCount - 1u)) : 0.5f;
        float bladeCenter = lerp(-0.75f, 0.75f, bladeN) * width;
        float bladeWidth = width * (useLod0 ? 0.30f : 0.35f);
        float bladePhaseOffset = (bladeN - 0.5f) * 0.6f;

        [loop]
        for (uint seg = 0u; seg < segments; ++seg)
        {
            float t0 = float(seg) / float(segments);
            float t1 = float(seg + 1u) / float(segments);

            float windSeg = (wind + bladePhaseOffset);
            float bend0 = t0;
            float bend1 = t1;

            float taper0 = useLod0 ? lerp(1.0f, 0.12f, t0) : 1.0f;
            float taper1 = useLod0 ? lerp(1.0f, 0.12f, t1) : 1.0f;
            float w0 = bladeWidth * taper0;
            float w1 = bladeWidth * taper1;

            float x0 = bladeCenter + windSeg * width * 1.6f * bend0;
            float x1 = bladeCenter + windSeg * width * 1.6f * bend1;

            float y0 = lerp(-height, height, t0);
            float y1 = lerp(-height, height, t1);

            float3 bL = float3(x0 - w0, y0, 0.0f);
            float3 bR = float3(x0 + w0, y0, 0.0f);
            float3 tL = float3(x1 - w1, y1, 0.0f);
            float3 tR = float3(x1 + w1, y1, 0.0f);

            float3 rbL;
            rbL.x = bL.x * cosR - bL.z * sinR + grass.Position.x;
            rbL.z = bL.x * sinR + bL.z * cosR + grass.Position.z;
            rbL.y = bL.y + grass.Position.y;
            float3 rbR;
            rbR.x = bR.x * cosR - bR.z * sinR + grass.Position.x;
            rbR.z = bR.x * sinR + bR.z * cosR + grass.Position.z;
            rbR.y = bR.y + grass.Position.y;
            float3 rtL;
            rtL.x = tL.x * cosR - tL.z * sinR + grass.Position.x;
            rtL.z = tL.x * sinR + tL.z * cosR + grass.Position.z;
            rtL.y = tL.y + grass.Position.y;
            float3 rtR;
            rtR.x = tR.x * cosR - tR.z * sinR + grass.Position.x;
            rtR.z = tR.x * sinR + tR.z * cosR + grass.Position.z;
            rtR.y = tR.y + grass.Position.y;

            uint dst = baseVertex + blade * (segments * 6u) + seg * 6u;
            float useTexture = useLod0 ? 0.0f : 1.0f;

            v.Padding1 = float2(useTexture, t0);
            v.Position = rbL; v.TexCoord = float2(0.0f, 1.0f - t0); ExpandedGrassBuffer[dst + 0u] = v;
            v.Padding1 = float2(useTexture, t1);
            v.Position = rtL; v.TexCoord = float2(0.0f, 1.0f - t1); ExpandedGrassBuffer[dst + 1u] = v;
            v.Padding1 = float2(useTexture, t0);
            v.Position = rbR; v.TexCoord = float2(1.0f, 1.0f - t0); ExpandedGrassBuffer[dst + 2u] = v;

            v.Padding1 = float2(useTexture, t0);
            v.Position = rbR; v.TexCoord = float2(1.0f, 1.0f - t0); ExpandedGrassBuffer[dst + 3u] = v;
            v.Padding1 = float2(useTexture, t1);
            v.Position = rtL; v.TexCoord = float2(0.0f, 1.0f - t1); ExpandedGrassBuffer[dst + 4u] = v;
            v.Padding1 = float2(useTexture, t1);
            v.Position = rtR; v.TexCoord = float2(1.0f, 1.0f - t1); ExpandedGrassBuffer[dst + 5u] = v;
        }
    }
}