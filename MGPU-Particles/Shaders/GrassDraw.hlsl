// GrassDraw.hlsl
// Шейдер для отрисовки травы с одной текстурой

cbuffer ObjectConstants : register(b0)
{
    float4x4 World;
    float4x4 TextureTransform;
}

cbuffer WorldConstants : register(b1)
{
    float4x4 View;
    float4x4 Proj;
    float4x4 ViewProj;
    float3 EyePos;
    float Padding;
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
    float3 Padding2;
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

StructuredBuffer<GrassData> GrassBuffer : register(t0);
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
    float3 WorldPos : POSITION; // Позиция травинки в мировом пространстве
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
    
    // Применяем мировую и видовую трансформации
    float4 worldPos = mul(float4(grass.Position, 1.0f), World);
    float4 viewPos = mul(worldPos, View);
    
    VSOutput output = (VSOutput) 0;
    output.WorldPos = viewPos;
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
    
    float cosR = cos(input.Rotation);
    float sinR = sin(input.Rotation);
    
    // Смещение относительно центра травинки
    float3 localOffset;
    localOffset.x = offset.x * width;
    localOffset.y = offset.y * height;
    localOffset.z = 0.0f;
    
    // Поворачиваем смещение
    float3 rotatedOffset;
    rotatedOffset.x = localOffset.x * cosR - localOffset.z * sinR;
    rotatedOffset.z = localOffset.x * sinR + localOffset.z * cosR;
    rotatedOffset.y = localOffset.y;
    
    // Ветер влияет на верхние вершины
    if (offset.y > 0)
    {
        rotatedOffset.x += windFactor * width * 2.0f;
    }
    
    // Мировая позиция вершины
    float3 worldPos = input.WorldPos + rotatedOffset;
    
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