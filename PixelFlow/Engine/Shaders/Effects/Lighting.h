//
//  Lighting.h - Particle Lighting Effects
//
//  Author: Yauheni Kozich
//  Created: 31.10.25
//  Updated: Production-ready version with NDC support
//

#ifndef Lighting_h
#define Lighting_h

#include <metal_stdlib>
#include "../Core/Common.h"
#include "../Core/Utils.h"
#include "../Compute/Simulation.h"
using namespace metal;

// ============================================================================
// LIGHTING CONSTANTS
// ============================================================================

// Glow
#define GLOW_FALLOFF_POWER 2.5
#define GLOW_BASE_INTENSITY 0.4
#define GLOW_MAX_INTENSITY 1.0

// Bloom
#define BLOOM_THRESHOLD 0.8
#define BLOOM_INTENSITY 0.5
#define BLOOM_RADIUS 1.5

// Ambient
#define AMBIENT_LIGHT_MIN 0.1
#define AMBIENT_LIGHT_MAX 0.3

// Storm
#define STORM_FLASH_INTENSITY 2.0
#define STORM_AMBIENT_BOOST 0.5

// ============================================================================
// GLOW FUNCTIONS
// ============================================================================

static inline float calculateGlow(float dist, float power, float intensity) {
    float glow = 1.0 - dist;
    glow = pow(max(glow, 0.0), power);
    return glow * clamp(intensity, 0.0, GLOW_MAX_INTENSITY);
}

static inline float3 applyParticleGlow(float3 baseColor, float dist, float power, float intensity) {
    float glow = calculateGlow(dist, power, intensity);
    return baseColor + float3(glow);
}

// ============================================================================
// DISTANCE ATTENUATION (2D)
// ============================================================================

static inline float calculateDistanceAttenuation2D(float2 position, float2 lightPosition, float maxDistance) {
    float distance = length(position - lightPosition);
    if (maxDistance <= 0.0) return 1.0;
    float normalizedDist = distance / maxDistance;
    float attenuation = 1.0 - saturate(normalizedDist);
    return attenuation * attenuation;
}

// ============================================================================
// GLOBAL LIGHT (NDC)
// ============================================================================

static inline float3 applyGlobalLight(
    float3 baseColor,
    float2 position,    // in NDC [-1,1]
    float3 lightColor,
    float intensity
) {
    // Convert NDC [-1,1] -> [0,1]
    float2 ndcPos = position * 0.5 + 0.5;
    float lightFactor = mix(0.7, 1.0, 1.0 - ndcPos.y);
    float3 lighting = lightColor * intensity * lightFactor;
    return baseColor * (1.0 + lighting);
}

// ============================================================================
// AMBIENT OCCLUSION
// ============================================================================

static inline float calculateAmbientOcclusion2D(float2 position, float particleDensity) {
    float ao = 1.0 - saturate(particleDensity * 0.1);
    return mix(AMBIENT_LIGHT_MIN, AMBIENT_LIGHT_MAX, ao);
}

// ============================================================================
// BLOOM EFFECT
// ============================================================================

static inline float3 applyBloomEffect(float3 color, float dist) {
    float brightness = dot(color, float3(0.299, 0.587, 0.114));
    if (brightness > BLOOM_THRESHOLD) {
        float bloomAmount = (brightness - BLOOM_THRESHOLD) / (1.0 - BLOOM_THRESHOLD);
        float bloomGlow = calculateGlow(dist, 2.0, BLOOM_INTENSITY);
        float3 bloom = color * bloomAmount * bloomGlow * BLOOM_RADIUS;
        return color + bloom;
    }
    return color;
}

// ============================================================================
// LIGHT SCATTERING
// ============================================================================

static inline float3 applyLightScattering(
    float3 baseColor,
    float2 position,
    float2 lightSource,
    float intensity
) {
    float2 toLight = lightSource - position;
    float distance = length(toLight);
    float scattering = exp(-distance * 0.001) * intensity;
    float3 scatteredLight = float3(1.0, 0.9, 0.8) * scattering;
    return baseColor + scatteredLight * 0.2;
}

// ============================================================================
// RIM LIGHT
// ============================================================================

static inline float3 applyRimLight(float3 baseColor, float dist, float3 rimColor, float rimPower) {
    float rim = smoothstep(0.3, 1.0, dist);
    rim = pow(rim, rimPower);
    return baseColor + rimColor * rim * 0.3;
}

// ============================================================================
// STATE-DEPENDENT LIGHTING
// ============================================================================

static inline float3 applyStateLighting(
    float3 baseColor,
    float2 position,
    float dist,
    float time,
    int state
) {
    float3 result = baseColor;

    switch (state) {
        case SIMULATION_STATE_LIGHTNING_STORM: {
            float flashSeed = floor(time * 5.0);
            float flash = hash(flashSeed) > 0.7 ? 1.0 : 0.0;
            float flashIntensity = flash * STORM_FLASH_INTENSITY * hash(flashSeed + 1.0);
            result *= (1.0 + STORM_AMBIENT_BOOST);
            if (flash > 0.5) {
                float3 flashColor = float3(0.8, 0.9, 1.0) * flashIntensity;
                result += flashColor * (1.0 - dist);
            }
            result = applyRimLight(result, dist, float3(0.3, 0.5, 1.0), 3.0);
            break;
        }
        case SIMULATION_STATE_COLLECTING:
        case SIMULATION_STATE_COLLECTED: {
            result = baseColor;
            float glow = calculateGlow(dist, 2.0, GLOW_BASE_INTENSITY * 0.7);
            result += float3(glow * 0.2);
            break;
        }
        case SIMULATION_STATE_CHAOTIC: {
            float pulse = sin(time * 3.0) * 0.5 + 0.5;
            float dynamicIntensity = GLOW_BASE_INTENSITY * (0.8 + pulse * 0.4);
            result = baseColor;
            result += calculateGlow(dist, GLOW_FALLOFF_POWER, dynamicIntensity);
            break;
        }
        case SIMULATION_STATE_IDLE:
        default: {
            result = baseColor;
            float glow = calculateGlow(dist, 2.0, GLOW_BASE_INTENSITY * 0.5);
            result += float3(glow * 0.2);
            break;
        }
    }

    return result;
}

// ============================================================================
// MAIN PARTICLE LIGHTING FUNCTION
// ============================================================================

static inline float3 calculateParticle2DLighting(
    float3 baseColor,
    float2 position,
    float dist,
    float time,
    int state,
    float brightnessBoost
) {
    float3 result = baseColor * brightnessBoost;
    result = applyStateLighting(result, position, dist, time, state);
    result = applyBloomEffect(result, dist);
    result = max(result, float3(0.0));
    return result;
}

// ============================================================================
// SIMPLE LIGHTING (fast path)
// ============================================================================

static inline float3 calculateSimple2DLighting(
    float3 baseColor,
    float dist,
    float glowIntensity
) {
    float glow = calculateGlow(dist, GLOW_FALLOFF_POWER, glowIntensity);
    return baseColor + float3(glow);
}

#endif /* Lighting_h */
