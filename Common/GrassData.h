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
    uint32_t Padding[3]; // Для выравнивания до 16 байт
};

// Константы эмиттера травы
struct GrassEmitterData
{
    // Только то, что реально используется
    uint32_t GrassCount;           // Количество травинок
    uint32_t GridSize;             // Размер сетки
    float WorldSize;                // Размер мира
    float QuadSize;                 // Размер квада
    float Time;                     // Время для анимации
    float WindStrength;             // Сила ветра
    uint32_t AtlasTextureCount;      // Количество текстур
    float Padding[3];                // Выравнивание до 16-байтной границы
};