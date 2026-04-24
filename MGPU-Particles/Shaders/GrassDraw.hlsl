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
    uint AtlasTextureCount;
    uint GpuStressIterations;
    uint Lod0BladeCount;
    uint Lod1BladeCount;
    float2 WindDirection;
    float2 Padding2;
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

GSOutput CreateQuadVertex(GSInput input, float2 offset, float2 uv, float windFactor, float useTexture, float bladeHeight01)
{
    GSOutput output;

    float3 worldOrigin = mul(float4(0.0f, 0.0f, 0.0f, 1.0f), World).xyz;
    float3 worldAxisX = mul(float4(1.0f, 0.0f, 0.0f, 1.0f), World).xyz - worldOrigin;
    float3 worldAxisY = mul(float4(0.0f, 1.0f, 0.0f, 1.0f), World).xyz - worldOrigin;
    float objectScaleX = max(length(worldAxisX), 1e-3f);
    float objectScaleY = max(length(worldAxisY), 1e-3f);

    float width = QuadSize * input.Scale * 0.5f * objectScaleX;
    float height = QuadSize * input.Scale * objectScaleY;

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
    float verticalOffset = offset.y * height;
    float bendFactor = saturate((offset.y + 1.0f) * 0.5f);
    float bendProfile = bendFactor * bendFactor;
    float2 windDir = WindDirection;
    if (dot(windDir, windDir) < 1e-6f) windDir = float2(1.0f, 0.0f);
    windDir = normalize(windDir);
    float2 bladeRightXZ = normalize(float2(rotatedRight.x, rotatedRight.z));
    float dirAlign = dot(windDir, bladeRightXZ);
    float directionalBend = (0.7f + 0.3f * windFactor) * WindStrength * WindAmplitude * width * 1.6f * bendProfile;
    sideOffset += directionalBend * dirAlign;
    // Natural blade arc: as wind bends the tip, it also slightly droops down.
    verticalOffset -= abs(directionalBend) * 0.35f * bendProfile;

    float3 worldPos = input.WorldPos + rotatedRight * sideOffset + up * verticalOffset;
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
    float windFactor = sin(Time * 2.0f * WindIntensity + windPhase);
    
    // Single-GPU path: approximate LOD0 by segmenting close blades.
    float distToEye = distance(EyePosW, grass.WorldPos);
    bool useLod0 = distToEye <= 300.0f;
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
                float y0 = lerp(-1.0f, 1.0f, t0);
                float y1 = lerp(-1.0f, 1.0f, t1);

                float taper0 = lerp(1.0f, 0.12f, t0);
                float taper1 = lerp(1.0f, 0.12f, t1);
                float xL0 = bladeCenter - bladeHalfWidth * taper0;
                float xR0 = bladeCenter + bladeHalfWidth * taper0;
                float xL1 = bladeCenter - bladeHalfWidth * taper1;
                float xR1 = bladeCenter + bladeHalfWidth * taper1;
                float windBlade = windFactor + bladePhaseOffset;

                triStream.Append(CreateQuadVertex(grass, float2(xL0, y0), float2(0.0f, 1.0f - t0), windBlade, useTexture, t0));
                triStream.Append(CreateQuadVertex(grass, float2(xL1, y1), float2(0.0f, 1.0f - t1), windBlade, useTexture, t1));
                triStream.Append(CreateQuadVertex(grass, float2(xR0, y0), float2(1.0f, 1.0f - t0), windBlade, useTexture, t0));
                triStream.Append(CreateQuadVertex(grass, float2(xR1, y1), float2(1.0f, 1.0f - t1), windBlade, useTexture, t1));
                triStream.RestartStrip();
            }
        }
    }
    else
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

            triStream.Append(CreateQuadVertex(grass, float2(xL, -1.0f), float2(0.0f, 1.0f), windFactor, useTexture, 0.0f));
            triStream.Append(CreateQuadVertex(grass, float2(xL, 1.0f), float2(0.0f, 0.0f), windFactor, useTexture, 1.0f));
            triStream.Append(CreateQuadVertex(grass, float2(xR, -1.0f), float2(1.0f, 1.0f), windFactor, useTexture, 0.0f));
            triStream.Append(CreateQuadVertex(grass, float2(xR, 1.0f), float2(1.0f, 0.0f), windFactor, useTexture, 1.0f));
            triStream.RestartStrip();
        }
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
    
    return float4(color.rgb * lighting, color.a);
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
    // Multi-GPU path: add frame-time wind deformation in VS so animation
    // remains visible even if expanded vertices are not re-generated every frame.
    // Use b1 (WorldConstants) only; expanded draw root signature does not bind b2.
    float bladeHeight01 = saturate(1.0f - v.TexCoord.y);
    float phase = pos.x * 0.5f + pos.z * 0.3f + TotalTime * 2.0f;
    float bend = (0.7f + 0.3f * sin(phase)) * bladeHeight01;
    pos.x += 0.8f * bend;
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