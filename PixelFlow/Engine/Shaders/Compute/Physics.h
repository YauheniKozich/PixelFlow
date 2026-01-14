//
//  Physics.h
//  PixelFlow
//
//  Created by Yauheni Kozich on 31.10.25.
//  Updated: 2025-01-04 - Removed duplicate constants (use Simulation.h)
//
//  Contains abstract physics calculations and particle dynamics
//
//  MAIN FEATURES:
//  - Particle physics implementation for GPU
//  - Support for various simulation states
//  - Optimized movement and collision calculations
//  - Boundary conditions and safety checks


#ifndef Physics_h
#define Physics_h

#include <metal_stdlib>
#include "../Core/Common.h"
#include "../Core/Utils.h"
#include "Simulation.h"
using namespace metal;

// ============================================================================
// Physics Constants
// ============================================================================

// Collection physics
#define COLLECTION_BASE_SPEED 150.0
#define COLLECTION_MIN_SPEED 5.0
#define COLLECTION_THRESHOLD 8.0
#define COLLECTION_VELOCITY_DAMPING 0.9

// Chaotic physics
#define CHAOTIC_VORTEX_STRENGTH 1.5
#define CHAOTIC_RADIAL_STRENGTH 0.3
#define CHAOTIC_CHAOS_STRENGTH 0.4
#define CHAOTIC_VERTICAL_IMPULSE 8.0
#define CHAOTIC_HORIZONTAL_IMPULSE 4.0
#define CHAOTIC_IMPULSE_PERIOD 1.5
#define CHAOTIC_VELOCITY_DAMPING 0.92
#define CHAOTIC_HIGH_SPEED_DAMPING 0.85
#define CHAOTIC_HIGH_SPEED_THRESHOLD 15.0

// Storm physics
#define STORM_ELECTRIC_FORCE 4.0
#define STORM_ELECTRIC_DAMPING 0.2
#define STORM_BASE_TURBULENCE 0.5
#define STORM_VELOCITY_DAMPING 0.98

// General physics
#define MAX_VELOCITY 40.0
#define BOUNDARY_BOUNCE_DAMPING 0.8
#define PARTICLE_PULSE_AMPLITUDE 0.1

// ============================================================================
// HELPER FUNCTIONS
// ============================================================================

static inline float safeDeltaTimeForPhysics(float dt) {
    return (isfinite(dt) && dt > MIN_DT && dt < MAX_DT) ? dt : DEFAULT_DT;
}


static inline float2 safeNormalize2(float2 v) {
    float len = length(v);
    return (len > MIN_VECTOR_LENGTH) ? (v / len) : float2(0.0);
}

static inline bool isFloatSafe(float value) {
    return isfinite(value) && abs(value) < MAX_FLOAT_VALUE;
}

static inline bool isFloat2Safe(float2 value) {
    return isFloatSafe(value.x) && isFloatSafe(value.y);
}

// ============================================================================
// MOVEMENT CALCULATION FUNCTIONS
// ============================================================================

static inline float2 calculateCollectionMovement(
    thread Particle& p,
    constant SimulationParams * params,
    float safeDt,
    device atomic_uint* collectedCounter
) {
    float2 pos = p.position.xy;
    float2 target = p.targetPosition.xy;
    float2 toTarget = target - pos;
    float distToTarget = length(toTarget);

    float baseSpeed = (params[0].collectionSpeed > 0.0)
        ? params[0].collectionSpeed * COLLECTION_BASE_SPEED
        : COLLECTION_BASE_SPEED;
    
    float maxSpeed = baseSpeed;
    float moveDistance = max(COLLECTION_MIN_SPEED, maxSpeed * safeDt);
    moveDistance = min(moveDistance, distToTarget);

    float2 prevPos = p.position.xy;

    if (distToTarget > COLLECTION_THRESHOLD * 0.1) {
        float2 direction = safeNormalize2(toTarget);
        p.position.xy += direction * moveDistance;
    }

    float2 newVelocity = (p.position.xy - prevPos) / safeDt;
    p.velocity.xy = mix(p.velocity.xy, newVelocity, COLLECTION_VELOCITY_DAMPING);

   
    if (distToTarget < COLLECTION_THRESHOLD && p.life >= PARTICLE_ALIVE) {
        p.life = PARTICLE_COLLECTED;
        atomic_fetch_add_explicit(collectedCounter, 1, memory_order_relaxed);
    }

    return p.velocity.xy;
}

// В calculateChaoticMovement замените существующую логику:
static inline float2 calculateChaoticMovement(
    thread Particle& p,
    uint id,
    constant SimulationParams * params,
    float safeDt
) {
    // Используем мои функции вместо старой логики
  //  float2 chaoticMovement = randomChaoticMotion(p.position.xy, params[0].time, id);
    
    // Или выберите другой вариант:
    float2 chaoticMovement = turbulentMotion(p.position.xy, params[0].time, id);
    // float2 chaoticMovement = fractalChaos(p.position.xy, params[0].time, id);
    
    // Применяем движение с коэффициентом скорости
    p.velocity.xy += chaoticMovement * 3.0;  // Настройте множитель по вкусу
    
    // Затухание скорости (сохраняем из оригинала)
    float velocityDamping = CHAOTIC_VELOCITY_DAMPING;
    float speed = length(p.velocity.xy);
    if (speed > CHAOTIC_HIGH_SPEED_THRESHOLD) {
        velocityDamping = CHAOTIC_HIGH_SPEED_DAMPING;
    }
    p.velocity.xy *= velocityDamping;

    return p.velocity.xy;
}


static inline void calculateStormMovement(
    thread Particle& p,
    uint id,
    constant SimulationParams * params
) {
    float seed = float(id) * 13.7;
    
    float fieldX = hash(seed + params[0].time * 1.5) - 0.5;
    float fieldY = hash(seed + params[0].time * 2.1 + 100.0) - 0.5;
    float2 electricForce = float2(fieldX, fieldY) * STORM_ELECTRIC_FORCE;
    p.velocity.xy += electricForce * STORM_ELECTRIC_DAMPING;

    float baseTurbulence = sin(params[0].time * 3.0 + seed) * STORM_BASE_TURBULENCE;
    p.velocity.xy += float2(baseTurbulence, baseTurbulence * 0.7);

    p.velocity.xy *= STORM_VELOCITY_DAMPING;

    float electricHue = hash(seed) * TWO_PI + params[0].time * 2.0;
    p.color = float4(
        0.3 + 0.7 * sin(electricHue),
        0.4 + 0.6 * sin(electricHue + 2.1),
        0.8 + 0.2 * sin(electricHue + 4.2),
        0.7 + 0.3 * sin(params[0].time * 3.0 + seed)
    );
}

// ============================================================================
// PARTICLE PROPERTY CALCULATIONS
// ============================================================================

static inline float calculateParticleSize(
    thread Particle& p,
    constant SimulationParams * params,
    uint id
) {
    float size;
    
    if (params[0].state == SIMULATION_STATE_COLLECTING ||
        params[0].state == SIMULATION_STATE_COLLECTED) {
        size = p.baseSize;
    } else {
        // Pulsating size in other modes
        float pulse = sin(p.life * 2.0 + float(id) * 0.01) * PARTICLE_PULSE_AMPLITUDE + 1.0;
        size = p.baseSize * pulse;
    }

    if (!isFloatSafe(size) || size < 0.0) {
        size = params[0].minParticleSize;
    }
    
    return clamp(size, params[0].minParticleSize, params[0].maxParticleSize);
}

// ============================================================================
// PHYSICS INTEGRATION
// ============================================================================

static inline void applyBoundaryConditionsForPhysics(thread Particle& p, float2 screenSize) {
    float safeWidth = max(screenSize.x, MIN_SCREEN_SIZE);
    float safeHeight = max(screenSize.y, MIN_SCREEN_SIZE);

    if (!isFloatSafe(p.position.x)) p.position.x = 0.0;
    if (!isFloatSafe(p.position.y)) p.position.y = 0.0;

    if (p.position.x < 0.0 || p.position.x > safeWidth) {
        p.velocity.x = -p.velocity.x * BOUNDARY_BOUNCE_DAMPING;
    }
    if (p.position.y < 0.0 || p.position.y > safeHeight) {
        p.velocity.y = -p.velocity.y * BOUNDARY_BOUNCE_DAMPING;
    }

    p.position.x = clamp(p.position.x, 0.0, safeWidth);
    p.position.y = clamp(p.position.y, 0.0, safeHeight);
}

static inline void integrateParticleForPhysics(
    thread Particle& p,
    float safeDt,
    float2 acceleration
) {
    p.velocity.xy += acceleration * safeDt;

    float speed = length(p.velocity.xy);
    if (!isFloatSafe(speed)) {
        p.velocity = float3(0.0, 0.0, 0.0);
        speed = 0.0;
    }

    if (speed > MAX_VELOCITY) {
        float2 velNorm = (speed > MIN_VECTOR_LENGTH)
            ? safeNormalize2(p.velocity.xy)
            : float2(0.0);
        p.velocity.xy = velNorm * MAX_VELOCITY;
    }

    p.position.xy += p.velocity.xy * safeDt;

    if (!isFloatSafe(p.position.x)) p.position.x = 0.0;
    if (!isFloatSafe(p.position.y)) p.position.y = 0.0;
}

// Apply pixel-perfect mode if enabled
static inline void applyPixelPerfectMode(thread Particle& p, uint pixelSizeMode) {
    if (pixelSizeMode == 1) {
        p.position.x = round(p.position.x);
        p.position.y = round(p.position.y);
    }
}

// ============================================================================
// COMPUTE SHADER - PARTICLE PHYSICS UPDATE
// ============================================================================

kernel void updateParticles(
    device Particle* particles [[buffer(0)]],
    constant SimulationParams * params [[buffer(1)]],
    device atomic_uint* collectedCounter [[buffer(2)]],
    uint id [[thread_position_in_grid]]
) {
    if (id >= params[0].particleCount) return;

    Particle p = particles[id];
    float safeDt = safeDeltaTimeForPhysics(params[0].deltaTime);

    if (p.life == PARTICLE_COLLECTED && params[0].state == SIMULATION_STATE_COLLECTED) {
        particles[id] = p;
        return;
    }

    bool skipIntegration = false;
    
    switch (params[0].state) {
        case SIMULATION_STATE_COLLECTING: {
            calculateCollectionMovement(p, params, safeDt, collectedCounter);
            skipIntegration = true;
            break;
        }
        
        case SIMULATION_STATE_COLLECTED: {
            p.velocity.xy = float2(0.0, 0.0);
            skipIntegration = true;
            break;
        }
        
        case SIMULATION_STATE_LIGHTNING_STORM: {
            calculateStormMovement(p, id, params);
            break;
        }
        
        case SIMULATION_STATE_IDLE:
        case SIMULATION_STATE_CHAOTIC:
        default: {
            // Для IDLE с включенным хаотичным движением используем новые функции
            if (params[0].state == SIMULATION_STATE_IDLE && params[0].idleChaoticMotion == 1) {
                // Более плавное и контролируемое хаотичное движение
                float2 chaoticMovement = randomChaoticMotion(p.position.xy, params[0].time, id);
                p.velocity.xy += chaoticMovement * 8.0;
                p.velocity.xy *= 0.93;
                
                // Дополнительно применяем стандартную интеграцию
                integrateParticleForPhysics(p, safeDt, float2(0.0, 0.0));
                applyBoundaryConditionsForPhysics(p, params[0].screenSize);
                skipIntegration = true; // Уже применили интеграцию
            } else {
                // Стандартное хаотичное движение для CHAOTIC и других состояний
                calculateChaoticMovement(p, id, params, safeDt);
            }
            break;
        }
    }


    // INTEGRATION: Only if position wasn't already updated
    if (!skipIntegration) {
        integrateParticleForPhysics(p, safeDt, float2(0.0, 0.0));
    }

    applyBoundaryConditionsForPhysics(p, params[0].screenSize);

    applyPixelPerfectMode(p, params[0].pixelSizeMode);

    p.size = calculateParticleSize(p, params, id);

    if (p.life >= PARTICLE_ALIVE) {
        p.life += safeDt;
        if (p.life > TWO_PI) {
            p.life -= TWO_PI;
        }
    }

    particles[id] = p;
}

#endif /* Physics_h */
