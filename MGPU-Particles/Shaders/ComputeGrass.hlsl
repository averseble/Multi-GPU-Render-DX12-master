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
    float3 Padding;
}

RWStructuredBuffer<GrassData> GrassBuffer : register(u0);

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