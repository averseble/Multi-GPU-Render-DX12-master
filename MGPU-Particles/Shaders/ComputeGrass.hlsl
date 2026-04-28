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
    float WindIntensity;
    float WindAmplitude;
    float Lod0BladeWidthScale;
    float Lod0BladeHeightScale;
    float Lod1BladeWidthScale;
    float Lod1BladeHeightScale;
    float Lod0SdofNaturalFreq;
    float Lod0SdofDampingRatio;
    float Lod0DistanceThreshold;
    float Lod1DistanceThreshold;
    uint AtlasTextureCount;
    uint GpuStressIterations;
    uint Lod0BladeCount;
    uint Lod1BladeCount;
    float2 WindDirection;
    uint WindOriginCount;
    float WindMapFalloff;
    float FieldInfluenceScale;
    float DebugNearestOriginTint;
    float Padding;
    float4 WindOriginData[4];
    float4 WindDirectionData[4];
}

cbuffer GrassCullData : register(b1)
{
    float4x4 World;
    float4x4 ViewProj;
    float3 EyePos;
    float MaxDistance;
    float Lod0Distance;
    float Lod1Distance;
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

float2 SampleWindGradient(float3 worldPos, float2 fallbackDir)
{
    float2 accum = float2(0.0f, 0.0f);
    float wsum = 0.0f;
    uint count = min(WindOriginCount, 4u);
    [loop]
    for (uint i = 0u; i < count; ++i)
    {
        float3 origin = WindOriginData[i].xyz;
        float radius = max(1.0f, WindOriginData[i].w);
        float2 dir = WindDirectionData[i].xy;
        float strength = max(0.0f, WindDirectionData[i].w);
        float d = distance(worldPos.xz, origin.xz);
        float t = saturate(1.0f - d / radius);
        float w = pow(t, max(0.1f, WindMapFalloff)) * strength;
        if (dot(dir, dir) > 1e-6f && w > 1e-6f)
        {
            accum += normalize(dir) * w;
            wsum += w;
        }
    }
    if (wsum > 1e-6f)
    {
        float2 dir = normalize(accum);
        float mag = saturate(wsum / max(1.0f, float(count)));
        return dir * mag;
    }
    float2 d0 = fallbackDir;
    if (dot(d0, d0) < 1e-6f) d0 = float2(1.0f, 0.0f);
    return normalize(d0);
}

float2 SampleNearestWindVector(float3 worldPos, float2 fallbackDir)
{
    uint count = min(WindOriginCount, 4u);
    float bestMetric = 1e30f;
    float2 bestVec = float2(0.0f, 0.0f);
    [loop]
    for (uint i = 0u; i < count; ++i)
    {
        float3 origin = WindOriginData[i].xyz;
        float radius = max(1.0f, WindOriginData[i].w);
        float2 dir = WindDirectionData[i].xy;
        float strength = max(0.0f, WindDirectionData[i].w);
        if (dot(dir, dir) < 1e-6f || strength <= 1e-6f)
            continue;
        float d = distance(worldPos.xz, origin.xz);
        float nd = d / radius;
        // Choose nearest by physical distance to avoid large-radius bias
        // forcing one origin to dominate the entire field direction.
        if (d < bestMetric)
        {
            bestMetric = d;
            float t = saturate(1.0f - nd);
            float w = pow(t, max(0.1f, WindMapFalloff)) * strength;
            bestVec = normalize(dir) * w;
        }
    }
    if (dot(bestVec, bestVec) > 1e-6f)
    {
        return bestVec;
    }
    return SampleWindGradient(worldPos, fallbackDir);
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

    float baseWidth = QuadSize * grass.Scale * 0.5f;
    float baseHeight = QuadSize * grass.Scale;
    float cosR = cos(grass.Rotation);
    float sinR = sin(grass.Rotation);
    float forceOmega = max(0.01f, 2.0f * WindIntensity);
    float forceSignal = sin(Time * forceOmega + grass.WindOffset);

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
    bool useLod1 = !useLod0 && distToEye <= Lod1Distance;
    bool useLod2 = !useLod0 && !useLod1;
    float wind = forceSignal;
    if (useLod0)
    {
        forceOmega = 2.0f;
        float wn = max(0.05f, Lod0SdofNaturalFreq);
        float zeta = max(0.01f, Lod0SdofDampingRatio);
        float num = wn * wn;
        float denA = (wn * wn - forceOmega * forceOmega);
        float denB = (2.0f * zeta * wn * forceOmega);
        float gain = num / sqrt(max(1e-6f, denA * denA + denB * denB));
        float phaseLag = atan2(denB, denA);
        wind = sin(Time * forceOmega + grass.WindOffset - phaseLag) * gain;
    }
    float ampScale = useLod0 ? 1.0f : WindAmplitude;
    wind *= (WindStrength * ampScale);
    float lodWidthScale = useLod0 ? Lod0BladeWidthScale : Lod1BladeWidthScale;
    float lodHeightScale = useLod0 ? Lod0BladeHeightScale : Lod1BladeHeightScale;
    float width = baseWidth * max(lodWidthScale, 0.05f);
    float height = baseHeight * max(lodHeightScale, 0.05f);
    uint segments = 1u;
    if (useLod0)
    {
        float windAbs = abs(wind);
        uint extraSeg = (uint)clamp(floor(windAbs * WindTessellationScale), 0.0f, 2.0f);
        segments = clamp(Lod0BaseSegments + extraSeg, 2u, 6u);
    }

    uint bladeCount = useLod0 ? clamp(Lod0BladeCount, 1u, 4u) : clamp(Lod1BladeCount, 1u, 4u);
    if (useLod2)
    {
        bladeCount = 1u;
        segments = 1u;
    }
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

            float windSeg = useLod2 ? 0.0f : (wind + bladePhaseOffset);
            float bend0 = t0 * t0;
            float bend1 = t1 * t1;

            float taper0 = useLod0 ? lerp(1.0f, 0.12f, t0) : 1.0f;
            float taper1 = useLod0 ? lerp(1.0f, 0.12f, t1) : 1.0f;
            float w0 = bladeWidth * taper0;
            float w1 = bladeWidth * taper1;

            float x0 = bladeCenter;
            float x1 = bladeCenter;

            float y0 = lerp(0.0f, height, t0);
            float y1 = lerp(0.0f, height, t1);

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

            float2 windVec = useLod0
                ? SampleNearestWindVector(worldCenter.xyz, WindDirection)
                : SampleWindGradient(worldCenter.xyz, WindDirection);
            float2 windDir = (dot(windVec, windVec) > 1e-6f) ? normalize(windVec) : float2(1.0f, 0.0f);
            float windFieldStrength = clamp(length(windVec) * FieldInfluenceScale, 0.0f, 8.0f);
            float directionalResponse = windSeg;
            float staticLay = useLod0 ? (0.9f * windFieldStrength) : 0.0f;
            float bendWorld0 = (staticLay + directionalResponse) * WindStrength * windFieldStrength * width * 1.6f * bend0;
            float bendWorld1 = (staticLay + directionalResponse) * WindStrength * windFieldStrength * width * 1.6f * bend1;
            float2 offset0 = windDir * bendWorld0;
            float2 offset1 = windDir * bendWorld1;
            rbL.xz += offset0;
            rbR.xz += offset0;
            rtL.xz += offset1;
            rtR.xz += offset1;
            // Apply tip droop proportional to bend for curved blade shape.
            rbL.y -= abs(bendWorld0) * 0.35f * bend0;
            rbR.y -= abs(bendWorld0) * 0.35f * bend0;
            rtL.y -= abs(bendWorld1) * 0.35f * bend1;
            rtR.y -= abs(bendWorld1) * 0.35f * bend1;

            uint dst = baseVertex + blade * (segments * 6u) + seg * 6u;
            // 0: LOD0 gradient, 1: textured LOD1, 2: textured LOD2 (lower mip in PS).
            float useTexture = useLod0 ? 0.0f : (useLod1 ? 1.0f : 2.0f);

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