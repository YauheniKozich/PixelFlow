//
//  Utils.h - Полезные утилиты для Metal шейдеров
//  ===============================================
//
//  Здесь живут маленькие, но важные функции-хелперы.
//  Они используются везде: в физике, рендеринге, эффектах.
//
//  Без этих функций анимации были бы статичными и предсказуемыми.
//  А так - частицы танцуют, мерцают и ведут себя интересно!
//
//  Автор: Yauheni Kozich
//  Создан: 31.10.25
//  Обновлен: 2025-01-10

#ifndef Utils_h
#define Utils_h

#include <metal_stdlib>
#include "Common.h"
#include "../Compute/Simulation.h"
using namespace metal;

static inline float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static inline float noise(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float n = i.x + i.y * 57.0 + i.z;

    return mix(mix(mix(hash(n + 0.0), hash(n + 1.0), f.x),
                   mix(hash(n + 57.0), hash(n + 58.0), f.x), f.y),
               mix(mix(hash(n + 113.0), hash(n + 114.0), f.x),
                   mix(hash(n + 170.0), hash(n + 171.0), f.x), f.y), f.z);
}

// Сильно рандомизированное движение

static inline float2 randomChaoticMotion(float2 position, float time, uint particleId) {
    float seed = float(particleId) * 13.7 + time * 0.01;
    
    // Генерируем несколько слоев случайности
    float noise1 = hash(seed);
    float noise2 = hash(seed + 17.3);
    float noise3 = hash(seed + 23.9);
    float noise4 = hash(seed + 31.1);
    
    // Комбинируем разные частоты движения
    float lowFreq = sin(time * 0.3 + noise1 * TWO_PI) * 2.0;
    float midFreq = cos(time * 1.2 + noise2 * TWO_PI) * 0.8;
    float highFreq = sin(time * 4.0 + noise3 * TWO_PI) * 0.3;
    
    // Добавляем импульсные движения (редкие, но сильные)
    float impulse = (hash(noise4 + time * 0.1) > 0.95) ?
        (hash(noise4 * 2.0) - 0.5) * 2.0 : 0.0;
    
    // Возвращаем 2D вектор смещения
    return float2(
        lowFreq + midFreq + highFreq + impulse,
        cos(time * 0.7 + noise1 * TWO_PI) * 0.5 +
        sin(time * 2.1 + noise2 * TWO_PI) * 0.2 +
        impulse * 0.5
    );
}

// Турбулентное движение

static inline float2 turbulentMotion(float2 position, float time, uint particleId) {
    // Базовый сид для частицы
    float baseSeed = float(particleId) * 17.3;
    
    // Создаем турбулентность с разными масштабами
    float2 offset = float2(0.0, 0.0);
    
    // Крупномасштабные вихри
    offset.x += sin(time * 0.2 + baseSeed) * 1.5;
    offset.y += cos(time * 0.15 + baseSeed * 1.3) * 1.5;
    
    // Среднемасштабные колебания
    offset.x += cos(time * 0.8 + baseSeed * 0.7) * 0.8;
    offset.y += sin(time * 1.1 + baseSeed * 1.1) * 0.8;
    
    // Мелкомасштабная дрожь
    offset.x += sin(time * 3.0 + baseSeed * 2.0) * 0.3;
    offset.y += cos(time * 3.5 + baseSeed * 2.5) * 0.3;
    
    // Случайные скачки
    float jumpTrigger = hash(baseSeed + floor(time * 0.5));
    if (jumpTrigger > 0.98) {
        offset.x += (hash(baseSeed * time) - 0.5) * 4.0;
        offset.y += (hash(baseSeed * time * 1.3) - 0.5) * 4.0;
    }
    
    return offset;
}

// Фрактальное хаотичное движение

static inline float2 fractalChaos(float2 position, float time, uint particleId) {
    float seed = float(particleId) + time * 0.01;
    float2 movement = float2(0.0, 0.0);
    
    float amplitude = 1.0;
    float frequency = 1.0;
    
    for (int i = 0; i < 4; i++) {
        float2 noisePos = float2(
            hash(seed * frequency + float(i) * 13.0),
            hash(seed * frequency * 1.7 + float(i) * 19.0)
        );
        
        movement.x += sin(time * frequency * 0.5 + noisePos.x * TWO_PI) * amplitude;
        movement.y += cos(time * frequency * 0.7 + noisePos.y * TWO_PI) * amplitude;
        
        amplitude *= 0.5;
        frequency *= 2.3;      
    }
    
    float impulseChance = hash(seed + floor(time));
    if (impulseChance > 0.97) {
        float impulseStrength = hash(seed * time) * 3.0;
        movement.x += (hash(seed * 2.0) - 0.5) * impulseStrength;
        movement.y += (hash(seed * 3.0) - 0.5) * impulseStrength;
    }
    
    return movement;
}

#endif /* Utils_h */
