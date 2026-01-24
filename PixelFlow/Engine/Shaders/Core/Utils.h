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

// ============================================================================
// HASH & NOISE CONSTANTS
// ============================================================================
constant float HASH_MULTIPLIER = 43758.5453123;  // Hash function multiplier

// ============================================================================
// CHAOTIC MOTION CONSTANTS
// ============================================================================
constant float CHAOTIC_PARTICLE_SEED_FACTOR = 13.7;
constant float CHAOTIC_TIME_SCALE = 0.01;
constant float CHAOTIC_LOW_FREQ_TIME = 0.3;
constant float CHAOTIC_LOW_FREQ_AMP = 2.0;
constant float CHAOTIC_MID_FREQ_TIME = 1.2;
constant float CHAOTIC_MID_FREQ_AMP = 0.8;
constant float CHAOTIC_HIGH_FREQ_TIME = 4.0;
constant float CHAOTIC_HIGH_FREQ_AMP = 0.3;
constant float CHAOTIC_Y_LOW_FREQ_TIME = 0.7;
constant float CHAOTIC_Y_LOW_FREQ_AMP = 0.5;
constant float CHAOTIC_Y_MID_FREQ_TIME = 2.1;
constant float CHAOTIC_Y_MID_FREQ_AMP = 0.2;
constant float CHAOTIC_IMPULSE_THRESHOLD = 0.95;
constant float CHAOTIC_IMPULSE_STRENGTH = 2.0;

// ============================================================================
// TURBULENT MOTION CONSTANTS
// ============================================================================
constant float TURBULENT_SEED_FACTOR = 17.3;
constant float TURBULENT_LARGE_FREQ_X = 0.2;
constant float TURBULENT_LARGE_FREQ_Y = 0.15;
constant float TURBULENT_LARGE_FREQ_Y_MOD = 1.3;
constant float TURBULENT_LARGE_AMP = 1.5;
constant float TURBULENT_MID_FREQ_X = 0.8;
constant float TURBULENT_MID_FREQ_X_MOD = 0.7;
constant float TURBULENT_MID_FREQ_Y = 1.1;
constant float TURBULENT_MID_FREQ_Y_MOD = 1.1;
constant float TURBULENT_MID_AMP = 0.8;
constant float TURBULENT_SMALL_FREQ_X = 3.0;
constant float TURBULENT_SMALL_FREQ_X_MOD = 2.0;
constant float TURBULENT_SMALL_FREQ_Y = 3.5;
constant float TURBULENT_SMALL_FREQ_Y_MOD = 2.5;
constant float TURBULENT_SMALL_AMP = 0.3;
constant float TURBULENT_JUMP_TRIGGER_THRESHOLD = 0.98;
constant float TURBULENT_JUMP_TIME_SCALE = 0.5;
constant float TURBULENT_JUMP_STRENGTH = 4.0;

// ============================================================================
// FRACTAL CHAOS CONSTANTS
// ============================================================================
constant float FRACTAL_SEED_TIME_SCALE = 0.01;
constant uint FRACTAL_OCTAVES = 4;
constant float FRACTAL_AMPLITUDE_DECAY = 0.5;
constant float FRACTAL_FREQUENCY_SCALE = 2.3;
constant float FRACTAL_FREQ_X_TIME = 0.5;
constant float FRACTAL_FREQ_Y_TIME = 0.7;
constant float FRACTAL_IMPULSE_THRESHOLD = 0.97;
constant float FRACTAL_IMPULSE_STRENGTH = 3.0;

static inline float hash(float n) {
    return fract(sin(n) * HASH_MULTIPLIER);
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
    float seed = float(particleId) * CHAOTIC_PARTICLE_SEED_FACTOR + time * CHAOTIC_TIME_SCALE;
    
    // Генерируем несколько слоев случайности
    float noise1 = hash(seed);
    float noise2 = hash(seed + 17.3);
    float noise3 = hash(seed + 23.9);
    float noise4 = hash(seed + 31.1);
    
    // Комбинируем разные частоты движения
    float lowFreq = sin(time * CHAOTIC_LOW_FREQ_TIME + noise1 * TWO_PI) * CHAOTIC_LOW_FREQ_AMP;
    float midFreq = cos(time * CHAOTIC_MID_FREQ_TIME + noise2 * TWO_PI) * CHAOTIC_MID_FREQ_AMP;
    float highFreq = sin(time * CHAOTIC_HIGH_FREQ_TIME + noise3 * TWO_PI) * CHAOTIC_HIGH_FREQ_AMP;
    
    // Добавляем импульсные движения (редкие, но сильные)
    float impulse = (hash(noise4 + time * 0.1) > CHAOTIC_IMPULSE_THRESHOLD) ?
        (hash(noise4 * 2.0) - 0.5) * CHAOTIC_IMPULSE_STRENGTH : 0.0;
    
    // Возвращаем 2D вектор смещения
    return float2(
        lowFreq + midFreq + highFreq + impulse,
        cos(time * CHAOTIC_Y_LOW_FREQ_TIME + noise1 * TWO_PI) * CHAOTIC_Y_LOW_FREQ_AMP +
        sin(time * CHAOTIC_Y_MID_FREQ_TIME + noise2 * TWO_PI) * CHAOTIC_Y_MID_FREQ_AMP +
        impulse * 0.5
    );
}

// Турбулентное движение

static inline float2 turbulentMotion(float2 position, float time, uint particleId) {
    // Spatially-correlated turbulent field in NDC space

    float baseSeed = float(particleId) * TURBULENT_SEED_FACTOR;

    // Scale position to control field density
    float2 fieldPos = position * 2.5;

    float2 offset = float2(0.0);

    // Large-scale vortices (spatial + temporal)
    offset.x += sin(fieldPos.y * TURBULENT_LARGE_FREQ_X +
                    time * 0.6 +
                    baseSeed) * TURBULENT_LARGE_AMP;

    offset.y += cos(fieldPos.x * TURBULENT_LARGE_FREQ_Y +
                    time * 0.6 +
                    baseSeed * TURBULENT_LARGE_FREQ_Y_MOD) * TURBULENT_LARGE_AMP;

    // Mid-scale turbulence
    offset.x += cos(fieldPos.x * TURBULENT_MID_FREQ_X +
                    time * 1.1 +
                    baseSeed * TURBULENT_MID_FREQ_X_MOD) * TURBULENT_MID_AMP;

    offset.y += sin(fieldPos.y * TURBULENT_MID_FREQ_Y +
                    time * 1.1 +
                    baseSeed * TURBULENT_MID_FREQ_Y_MOD) * TURBULENT_MID_AMP;

    // Small-scale jitter
    offset.x += sin((fieldPos.x + fieldPos.y) * TURBULENT_SMALL_FREQ_X +
                    time * 2.0 +
                    baseSeed * TURBULENT_SMALL_FREQ_X_MOD) * TURBULENT_SMALL_AMP;

    offset.y += cos((fieldPos.y - fieldPos.x) * TURBULENT_SMALL_FREQ_Y +
                    time * 2.0 +
                    baseSeed * TURBULENT_SMALL_FREQ_Y_MOD) * TURBULENT_SMALL_AMP;

    // Rare spatial impulses
    float jumpSeed = hash(floor(fieldPos.x * 3.0) +
                          floor(fieldPos.y * 3.0) * 17.0 +
                          floor(time * TURBULENT_JUMP_TIME_SCALE) +
                          baseSeed);

    if (jumpSeed > TURBULENT_JUMP_TRIGGER_THRESHOLD) {
        float impulse = (hash(jumpSeed + baseSeed) - 0.5) * TURBULENT_JUMP_STRENGTH;
        offset += impulse;
    }

    return offset;
}

// Фрактальное хаотичное движение

static inline float2 fractalChaos(float2 position, float time, uint particleId) {
    float seed = float(particleId) + time * FRACTAL_SEED_TIME_SCALE;
    float2 movement = float2(0.0, 0.0);
    
    float amplitude = 1.0;
    float frequency = 1.0;
    
    for (uint i = 0; i < FRACTAL_OCTAVES; i++) {
        float2 noisePos = float2(
            hash(seed * frequency + float(i) * 13.0),
            hash(seed * frequency * 1.7 + float(i) * 19.0)
        );
        
        movement.x += sin(time * frequency * FRACTAL_FREQ_X_TIME + noisePos.x * TWO_PI) * amplitude;
        movement.y += cos(time * frequency * FRACTAL_FREQ_Y_TIME + noisePos.y * TWO_PI) * amplitude;
        
        amplitude *= FRACTAL_AMPLITUDE_DECAY;
        frequency *= FRACTAL_FREQUENCY_SCALE;
    }
    
    float impulseChance = hash(seed + floor(time));
    if (impulseChance > FRACTAL_IMPULSE_THRESHOLD) {
        float impulseStrength = hash(seed * time) * FRACTAL_IMPULSE_STRENGTH;
        movement.x += (hash(seed * 2.0) - 0.5) * impulseStrength;
        movement.y += (hash(seed * 3.0) - 0.5) * impulseStrength;
    }
    
    return movement;
}

#endif /* Utils_h */
