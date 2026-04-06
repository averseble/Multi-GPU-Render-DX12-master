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
    uint AtlasTextureCount;
    uint GpuStressIterations;
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
    float2 Padding1;
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
};

GSOutput CreateQuadVertex(GSInput input, float2 offset, float2 uv, float windFactor)
{
    GSOutput output;
    
    float width = QuadSize * input.Scale * 0.5f;
    float height = QuadSize * input.Scale;

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
    if (offset.y > 0.0f)
    {
        sideOffset += windFactor * width * 2.0f;
    }

    float3 worldPos = input.WorldPos + rotatedRight * sideOffset + up * verticalOffset;
#endif
    
    output.WorldPos = worldPos;
    output.PositionH = mul(float4(worldPos, 1.0f), ViewProj);
    output.TexCoord = uv;
    output.Normal = float3(0, 1, 0);
    output.Alpha = 1.0f;
    
    return output;
}

[maxvertexcount(4)]
void GS(point GSInput input[1], inout TriangleStream<GSOutput> triStream)
{
    GSInput grass = input[0];
    
    // Эффект ветра
    float windPhase = grass.WorldPos.x * 0.5f + grass.WorldPos.z * 0.3f + grass.WindOffset;
    float windFactor = sin(Time * 2.0f + windPhase) * WindStrength;
    
    // Создаем квад из 4 вершин
    // Левый-нижний
    triStream.Append(CreateQuadVertex(grass, float2(-1, -1), float2(0, 1), windFactor));
    // Левый-верхний
    triStream.Append(CreateQuadVertex(grass, float2(-1, 1), float2(0, 0), windFactor));
    // Правый-нижний
    triStream.Append(CreateQuadVertex(grass, float2(1, -1), float2(1, 1), windFactor));
    // Правый-верхний
    triStream.Append(CreateQuadVertex(grass, float2(1, 1), float2(1, 0), windFactor));
    
    triStream.RestartStrip();
}

// Пиксельный шейдер
struct PSInput
{
    float4 PositionH : SV_POSITION;
    float2 TexCoord : TEXCOORD0;
    float3 WorldPos : WORLD_POS;
    float3 Normal : NORMAL;
    float Alpha : ALPHA;
};

float4 PS(PSInput input) : SV_Target
{
    float4 color = GrassTexture.Sample(Sampler, input.TexCoord);
    
    clip(color.a - 0.1f);
    
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
    float4 posW = mul(float4(v.Position, 1.0f), World);
    o.PositionH = mul(posW, ViewProj);
    o.TexCoord = v.TexCoord;
    o.WorldPos = posW.xyz;
    o.Normal = float3(0.0f, 1.0f, 0.0f);
    o.Alpha = 1.0f;
    return o;
}

float4 PS_Expanded(ExpandedVSOut input) : SV_Target
{
    clip(input.Alpha - 0.5f);
    float4 color = GrassTexture.Sample(Sampler, input.TexCoord);
    clip(color.a - 0.1f);
    float3 lightDir = normalize(float3(0.5f, -0.5f, 0.5f));
    float diff = max(0.3f, dot(input.Normal, -lightDir));
    float3 ambient = float3(0.2f, 0.2f, 0.2f);
    float3 lighting = ambient + diff;
    return float4(color.rgb * lighting, color.a);
}