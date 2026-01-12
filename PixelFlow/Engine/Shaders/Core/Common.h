//
//  Common.h - Общие определения для системы частиц PixelFlow
//  ========================================================
//
//  ЭТОТ ФАЙЛ - СЕРДЦЕ СИСТЕМЫ!
//  Здесь живут структуры данных, которые связывают Swift и Metal.
//
//  Представь: CPU (Swift) готовит данные, GPU (Metal) их использует.
//  Любая ошибка здесь = крах всей симуляции.
//
//  Автор: Yauheni Kozich
//  Создан: 31.10.25
//  Обновлен: 2025-01-10 

#ifndef Common_h
#define Common_h

#include <metal_stdlib>
using namespace metal;

struct Particle {
    float3 position;
    float3 velocity;
    float3 targetPosition;
    float4 color;
    float4 originalColor;
    float size;
    float baseSize;
    float life;
    uint idleChaoticMotion;
};

// ============================================================================
// SIMULATION PARAMETERS - CRITICAL STRUCTURE
// ============================================================================
// 
// CRITICAL: Must match SimulationParams in Particle.swift EXACTLY
// - Field order MUST be identical
// - Field types MUST be identical  
// - Total size MUST be exactly 256 bytes for Metal buffer alignment
//
// Structure layout breakdown:
// - uint fields (state, pixelSizeMode, colorsLocked, _pad1): 16 bytes
// - float fields (deltaTime, collectionSpeed, brightnessBoost, _pad2): 16 bytes
// - float2 fields (screenSize, _pad3): 16 bytes
// - particle params (minParticleSize, maxParticleSize, time, particleCount, idleChaoticMotion, padding): 24 bytes
// - reserved array (11 * float4): 176 bytes
// - final padding: 8 bytes
// Total: 16 + 16 + 16 + 24 + 176 + 8 = 256 bytes
//
// DO NOT modify field order or types without updating Particle.swift!
// ============================================================================
struct SimulationParams {
    uint state;
    uint pixelSizeMode;
    uint colorsLocked;
    uint _pad1;
    float deltaTime;
    float collectionSpeed;
    float brightnessBoost;

    // Выравнивание для GPU
    float _pad2;
    float2 screenSize;
    float2 _pad3;
    float minParticleSize;
    float maxParticleSize;
    float time;
    uint particleCount;
    uint idleChaoticMotion;
    uint padding;
    float4 _reserved[11];  // 176 bytes (11 * 16)
};


#endif /* Common_h */

