// GrassDraw.hlsl
// Шейдер для отрисовки травы с одной текстурой

// Debug switch:
// 1 -> force all grass to a fixed world-space quad (diagnostic mode)
// 0 -> normal grass rendering path
#define GRASS_DEBUG_FIXED_WORLD 0

cbuffer ObjectConstants : register(b0)
{
    float4x4 World;
    float4x4 TextureTransform;
}

cbuffer WorldConstants : register(b1)
{
    float4x4 View;
    float4x4 InvView;
    float4x4 Proj;
    float4x4 InvProj;
    float4x4 ViewProj;
    float4x4 InvViewProj;
    float4x4 ViewProjTex;
    float4x4 ShadowTransform;
    float3 EyePosW;
    float debugMap;
    float2 RenderTargetSize;
    float2 InvRenderTargetSize;
    float NearZ;
    float FarZ;
    float TotalTime;
    float DeltaTime;
    float4 AmbientLight;
    float3 CameraForwardVector;
    float padding;
}

cbuffer GrassEmitterData : register(b2)
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
    float2 Padding2;
    float4 WindOriginData[4];
    float4 WindDirectionData[4];
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

uint FindNearestWindOriginIndex(float3 worldPos)
{
    uint count = min(WindOriginCount, 4u);
    float bestD = 1e30f;
    uint bestI = 0u;
    [loop]
    for (uint i = 0u; i < count; ++i)
    {
        float d = distance(worldPos.xz, WindOriginData[i].xz);
        if (d < bestD)
        {
            bestD = d;
            bestI = i;
        }
    }
    return bestI;
}

float3 OriginDebugColor(uint idx)
{
    if (idx == 0u) return float3(1.0, 0.2, 0.2); // red
    if (idx == 1u) return float3(0.2, 1.0, 0.2); // green
    if (idx == 2u) return float3(0.2, 0.4, 1.0); // blue
    return float3(1.0, 1.0, 0.2);                // yellow
}

struct GrassData
{
    float3 Position;
    float Scale;
    float Rotation;
    float WindOffset;
    uint TextureIndex;
    uint3 Padding3;
};

struct GrassRenderVertex
{
    float3 Position;
    float Padding0;
    float2 TexCoord;
    float2 ExtraData; // x = useTexture(0/1), y = bladeHeight01
};

StructuredBuffer<GrassData> GrassBuffer : register(t0);
StructuredBuffer<GrassRenderVertex> ExpandedGrassVertices : register(t8);
StructuredBuffer<uint> VisibleVertexCounter : register(t9);
Texture2D GrassTexture : register(t1);
SamplerState Sampler : register(s0);

// Вершинный шейдер - читаем данные травы и передаем в геометрический
struct VSInput
{
    uint VertexID : SV_VertexID;
    uint InstanceID : SV_InstanceID;
};

struct VSOutput
{
    float3 WorldPos : POSITION; // blade center in world space
    float Scale : SCALE;
    float Rotation : ROTATION;
    float WindOffset : WINDOFFSET;
    uint TextureIndex : TEX_INDEX;
    uint InstanceID : INSTANCE_ID;
};

VSOutput VS(VSInput input)
{
   // Читаем данные травинки по InstanceID (рендерим все травинки сразу)
    GrassData grass = GrassBuffer[input.InstanceID];
    
    // Применяем мировую трансформацию
    float4 worldPos = mul(float4(grass.Position, 1.0f), World);
    
    VSOutput output = (VSOutput) 0;
    // Keep wind phase and placement in world space so camera motion does not move blades.
    output.WorldPos = worldPos.xyz;
    output.Scale = grass.Scale;
    output.Rotation = grass.Rotation;
    output.WindOffset = grass.WindOffset;
    output.TextureIndex = grass.TextureIndex;
    output.InstanceID = input.InstanceID;
    
    return output;
}

// Геометрический шейдер
struct GSInput
{
    float3 WorldPos : POSITION;
    float Scale : SCALE;
    float Rotation : ROTATION;
    float WindOffset : WINDOFFSET;
    uint TextureIndex : TEX_INDEX;
    uint InstanceID : INSTANCE_ID;
};

struct GSOutput
{
    float4 PositionH : SV_POSITION;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : WORLD_POS;
    float3 Normal : NORMAL;
    float Alpha : ALPHA;
    float UseTexture : TEXCOORD1;
    float BladeHeight01 : TEXCOORD2;
};

GSOutput CreateQuadVertex(GSInput input, float2 offset, float2 uv, float windFactor, float useTexture,
                          float bladeHeight01, float bladeWidthScale, float bladeHeightScale)
{
    GSOutput output;

    float3 worldOrigin = mul(float4(0.0f, 0.0f, 0.0f, 1.0f), World).xyz;
    float3 worldAxisX = mul(float4(1.0f, 0.0f, 0.0f, 1.0f), World).xyz - worldOrigin;
    float3 worldAxisY = mul(float4(0.0f, 1.0f, 0.0f, 1.0f), World).xyz - worldOrigin;
    float objectScaleX = max(length(worldAxisX), 1e-3f);
    float objectScaleY = max(length(worldAxisY), 1e-3f);

    float width = QuadSize * input.Scale * 0.5f * objectScaleX * max(bladeWidthScale, 0.05f);
    float height = QuadSize * input.Scale * objectScaleY * max(bladeHeightScale, 0.05f);

#if GRASS_DEBUG_FIXED_WORLD
    const float3 debugCenterW = float3(0.0f, 0.0f, 0.0f);
    float3 up = float3(0.0f, 1.0f, 0.0f);
    float3 right = float3(1.0f, 0.0f, 0.0f);
    float sideOffset = offset.x * width;
    float verticalOffset = offset.y * height;
    float3 worldPos = debugCenterW + right * sideOffset + up * verticalOffset;
#else
    
    // Build a camera-facing basis in world space, anchored at blade center.
    float3 toEye = EyePosW - input.WorldPos;
    toEye.y = 0.0f;
    float toEyeLen2 = dot(toEye, toEye);
    float3 forward = (toEyeLen2 > 1e-6f) ? normalize(toEye) : float3(0.0f, 0.0f, 1.0f);
    float3 up = float3(0.0f, 1.0f, 0.0f);
    float3 right = normalize(cross(up, forward));

    // Per-blade yaw variation around world up.
    float cosR = cos(input.Rotation);
    float sinR = sin(input.Rotation);
    float3 rotatedRight = right * cosR + forward * sinR;

    float sideOffset = offset.x * width;
    float verticalOffset = saturate(offset.y) * height;
    float bendFactor = saturate(offset.y);
    float bendProfile = bendFactor * bendFactor;
    float2 windVec = SampleWindGradient(input.WorldPos, WindDirection);
    if (useTexture < 0.5f)
    {
        // LOD0: use nearest field vector for clear directional lay.
        windVec = SampleNearestWindVector(input.WorldPos, WindDirection);
    }
    float2 windDir = (dot(windVec, windVec) > 1e-6f) ? normalize(windVec) : float2(1.0f, 0.0f);
    float windFieldStrength = clamp(length(windVec) * FieldInfluenceScale, 0.0f, 8.0f);
    float ampScale = (useTexture > 0.5f) ? WindAmplitude : 1.0f;
    // Keep a preferred wind direction but allow meaningful oscillation around it.
    float directionalResponse = windFactor;
    float staticLay = 0.9f * windFieldStrength; // strong steady lay toward local field
    float directionalBend = (staticLay + directionalResponse) * WindStrength * ampScale * windFieldStrength * width * 1.6f * bendProfile;
    // LOD0/LOD1 bend direction follows the vector field directly in world XZ.
    float3 worldWindOffset = float3(windDir.x, 0.0f, windDir.y) * directionalBend;
    // Natural blade arc: as wind bends the tip, it also slightly droops down.
    verticalOffset -= abs(directionalBend) * 0.35f * bendProfile;

    float3 worldPos = input.WorldPos + rotatedRight * sideOffset + up * verticalOffset + worldWindOffset;
#endif
    
    output.WorldPos = worldPos;
    output.PositionH = mul(float4(worldPos, 1.0f), ViewProj);
    output.TexCoord = uv;
    output.Normal = float3(0, 1, 0);
    output.Alpha = 1.0f;
    output.UseTexture = useTexture;
    output.BladeHeight01 = bladeHeight01;
    
    return output;
}

[maxvertexcount(64)]
void GS(point GSInput input[1], inout TriangleStream<GSOutput> triStream)
{
    GSInput grass = input[0];
    
    // Эффект ветра
    float windPhase = grass.WorldPos.x * 0.5f + grass.WorldPos.z * 0.3f + grass.WindOffset;
    float forceOmega = max(0.01f, 2.0f * WindIntensity);
    float forceSignal = sin(Time * forceOmega + windPhase);
    
    // Single-GPU path: approximate LOD0 by segmenting close blades.
    float distToEye = distance(EyePosW, grass.WorldPos);
    bool useLod0 = distToEye <= Lod0DistanceThreshold;
    bool useLod1 = !useLod0 && distToEye <= Lod1DistanceThreshold;
    bool useLod2 = !useLod0 && !useLod1;
    float windFactor = forceSignal;
    if (useLod0)
    {
        // Harmonic response of SDOF oscillator to sinusoidal forcing.
        float wn = max(0.05f, Lod0SdofNaturalFreq);
        float zeta = max(0.01f, Lod0SdofDampingRatio);
        // LOD0 is decoupled from generic wind intensity.
        forceOmega = 2.0f;
        float num = wn * wn;
        float denA = (wn * wn - forceOmega * forceOmega);
        float denB = (2.0f * zeta * wn * forceOmega);
        float gain = num / sqrt(max(1e-6f, denA * denA + denB * denB));
        float phaseLag = atan2(denB, denA);
        windFactor = sin(Time * forceOmega + windPhase - phaseLag) * gain;
        // LOD0 uses SDOF response amplitude directly.
    }
    float bladeWidthScale = useLod0 ? Lod0BladeWidthScale : Lod1BladeWidthScale;
    float bladeHeightScale = useLod0 ? Lod0BladeHeightScale : Lod1BladeHeightScale;
    if (useLod0)
    {
        // Near-field: render several thin separated strips per instance
        // so the silhouette reads as individual blades rather than one card.
        const uint bladeCount = clamp(Lod0BladeCount, 1u, 4u);
        const uint segments = 4u;
        const float useTexture = 0.0f;
        const float bladeHalfWidth = 0.04f;
        const float bladeSpread = 0.75f;

        [loop]
        for (uint blade = 0u; blade < bladeCount; ++blade)
        {
            float bladeN = (bladeCount > 1u) ? (float(blade) / float(bladeCount - 1u)) : 0.5f;
            float bladeCenter = lerp(-bladeSpread, bladeSpread, bladeN);
            float bladePhaseOffset = (bladeN - 0.5f) * 0.6f;

            [loop]
            for (uint seg = 0u; seg < segments; ++seg)
            {
                float t0 = float(seg) / float(segments);
                float t1 = float(seg + 1u) / float(segments);
                float y0 = t0;
                float y1 = t1;

                float taper0 = lerp(1.0f, 0.12f, t0);
                float taper1 = lerp(1.0f, 0.12f, t1);
                float xL0 = bladeCenter - bladeHalfWidth * taper0;
                float xR0 = bladeCenter + bladeHalfWidth * taper0;
                float xL1 = bladeCenter - bladeHalfWidth * taper1;
                float xR1 = bladeCenter + bladeHalfWidth * taper1;
                float windBlade = windFactor + bladePhaseOffset;

                triStream.Append(CreateQuadVertex(grass, float2(xL0, y0), float2(0.0f, 1.0f - t0), windBlade, useTexture, t0, bladeWidthScale, bladeHeightScale));
                triStream.Append(CreateQuadVertex(grass, float2(xL1, y1), float2(0.0f, 1.0f - t1), windBlade, useTexture, t1, bladeWidthScale, bladeHeightScale));
                triStream.Append(CreateQuadVertex(grass, float2(xR0, y0), float2(1.0f, 1.0f - t0), windBlade, useTexture, t0, bladeWidthScale, bladeHeightScale));
                triStream.Append(CreateQuadVertex(grass, float2(xR1, y1), float2(1.0f, 1.0f - t1), windBlade, useTexture, t1, bladeWidthScale, bladeHeightScale));
                triStream.RestartStrip();
            }
        }
    }
    else if (useLod1)
    {
        const uint bladeCount = clamp(Lod1BladeCount, 1u, 4u);
        const float useTexture = 1.0f;
        const float bladeHalfWidth = 0.16f;
        const float bladeSpread = 0.9f;
        [loop]
        for (uint blade = 0u; blade < bladeCount; ++blade)
        {
            float bladeN = (bladeCount > 1u) ? (float(blade) / float(bladeCount - 1u)) : 0.5f;
            float bladeCenter = lerp(-bladeSpread, bladeSpread, bladeN);
            float xL = bladeCenter - bladeHalfWidth;
            float xR = bladeCenter + bladeHalfWidth;

            triStream.Append(CreateQuadVertex(grass, float2(xL, 0.0f), float2(0.0f, 1.0f), windFactor, useTexture, 0.0f, bladeWidthScale, bladeHeightScale));
            triStream.Append(CreateQuadVertex(grass, float2(xL, 1.0f), float2(0.0f, 0.0f), windFactor, useTexture, 1.0f, bladeWidthScale, bladeHeightScale));
            triStream.Append(CreateQuadVertex(grass, float2(xR, 0.0f), float2(1.0f, 1.0f), windFactor, useTexture, 0.0f, bladeWidthScale, bladeHeightScale));
            triStream.Append(CreateQuadVertex(grass, float2(xR, 1.0f), float2(1.0f, 0.0f), windFactor, useTexture, 1.0f, bladeWidthScale, bladeHeightScale));
            triStream.RestartStrip();
        }
    }
    else
    {
        // LOD2: maximum optimization, no wind, single card.
        const float useTexture = 2.0f; // Mark LOD2 so pixel shader can sample lower mip.
        const float w = 0.10f;
        triStream.Append(CreateQuadVertex(grass, float2(-w, 0.0f), float2(0.0f, 1.0f), 0.0f, useTexture, 0.0f, Lod1BladeWidthScale, Lod1BladeHeightScale));
        triStream.Append(CreateQuadVertex(grass, float2(-w, 1.0f), float2(0.0f, 0.0f), 0.0f, useTexture, 1.0f, Lod1BladeWidthScale, Lod1BladeHeightScale));
        triStream.Append(CreateQuadVertex(grass, float2(w, 0.0f), float2(1.0f, 1.0f), 0.0f, useTexture, 0.0f, Lod1BladeWidthScale, Lod1BladeHeightScale));
        triStream.Append(CreateQuadVertex(grass, float2(w, 1.0f), float2(1.0f, 0.0f), 0.0f, useTexture, 1.0f, Lod1BladeWidthScale, Lod1BladeHeightScale));
        triStream.RestartStrip();
    }
}

// Пиксельный шейдер
struct PSInput
{
    float4 PositionH : SV_POSITION;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : WORLD_POS;
    float3 Normal : NORMAL;
    float Alpha : ALPHA;
    float UseTexture : TEXCOORD1;
    float BladeHeight01 : TEXCOORD2;
};

float4 PS(PSInput input) : SV_Target
{
    float4 color;
    if (input.UseTexture > 0.5f)
    {
        // LOD2 uses an explicit higher mip level for cheaper texture sampling.
        if (input.UseTexture > 1.5f)
            color = GrassTexture.SampleLevel(Sampler, input.TexCoord, 3.0f);
        else
            color = GrassTexture.Sample(Sampler, input.TexCoord);
        clip(color.a - 0.1f);
    }
    else
    {
        float t = saturate(input.BladeHeight01);
        float3 base = float3(0.10f, 0.38f, 0.10f);
        float3 tip = float3(0.32f, 0.78f, 0.20f);
        color = float4(lerp(base, tip, t), 1.0f);
    }
    
    // Простое освещение
    float3 lightDir = normalize(float3(0.5f, -0.5f, 0.5f));
    float diff = max(0.3f, dot(input.Normal, -lightDir));
    
    float3 ambient = float3(0.2f, 0.2f, 0.2f);
    float3 lighting = ambient + diff;
    float3 outRgb = color.rgb * lighting;
    if (DebugNearestOriginTint > 0.5f)
    {
        const uint i = FindNearestWindOriginIndex(input.WorldPos);
        const float3 tint = OriginDebugColor(i);
        outRgb = lerp(outRgb, tint, 0.65f);
    }
    return float4(outRgb, color.a);
}

struct ExpandedVSOut
{
    float4 PositionH : SV_POSITION;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : WORLD_POS;
    float3 Normal : NORMAL;
    float Alpha : ALPHA;
    float UseTexture : TEXCOORD1;
    float BladeHeight01 : TEXCOORD2;
};

ExpandedVSOut VS_Expanded(uint vertexID : SV_VertexID)
{
    ExpandedVSOut o = (ExpandedVSOut)0;
    uint visibleVertexCount = VisibleVertexCounter[0];
    if (vertexID >= visibleVertexCount)
    {
        o.PositionH = float4(0.0f, 0.0f, 0.0f, 0.0f);
        o.TexCoord = float2(0.0f, 0.0f);
        o.WorldPos = float3(0.0f, 0.0f, 0.0f);
        o.Normal = float3(0.0f, 1.0f, 0.0f);
        o.Alpha = 0.0f;
        return o;
    }
    GrassRenderVertex v = ExpandedGrassVertices[vertexID];
    float3 pos = v.Position;
    float4 posW = mul(float4(pos, 1.0f), World);
    o.PositionH = mul(posW, ViewProj);
    o.TexCoord = v.TexCoord;
    o.WorldPos = posW.xyz;
    o.Normal = float3(0.0f, 1.0f, 0.0f);
    o.Alpha = 1.0f;
    o.UseTexture = v.ExtraData.x;
    o.BladeHeight01 = v.ExtraData.y;
    return o;
}

float4 PS_Expanded(ExpandedVSOut input) : SV_Target
{
    clip(input.Alpha - 0.5f);
    float4 color;
    if (input.UseTexture > 0.5f)
    {
        if (input.UseTexture > 1.5f)
            color = GrassTexture.SampleLevel(Sampler, input.TexCoord, 3.0f);
        else
            color = GrassTexture.Sample(Sampler, input.TexCoord);
        clip(color.a - 0.1f);
    }
    else
    {
        float t = saturate(input.BladeHeight01);
        float3 base = float3(0.10f, 0.38f, 0.10f);
        float3 tip = float3(0.32f, 0.78f, 0.20f);
        color = float4(lerp(base, tip, t), 1.0f);
    }
    float3 lightDir = normalize(float3(0.5f, -0.5f, 0.5f));
    float diff = max(0.3f, dot(input.Normal, -lightDir));
    float3 ambient = float3(0.2f, 0.2f, 0.2f);
    float3 lighting = ambient + diff;
    return float4(color.rgb * lighting, color.a);
}