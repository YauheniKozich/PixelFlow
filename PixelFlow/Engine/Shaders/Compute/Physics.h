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
#define COLLECTION_BASE_SPEED          30.0   // pixels/sec (scaled by collectionSpeed)
#define COLLECTION_MIN_SPEED           0.25   // pixels (minimum step)
#define COLLECTION_SNAP_PIXELS        1.0
#define COLLECTION_MOVE_THRESHOLD      0.01
#define COLLECTION_VELOCITY_DAMPING    0.9

#define CHAOTIC_MOVEMENT_SCALE         0.08  // reduced chaotic movement scale
#define CHAOTIC_VELOCITY_DAMPING_NORMAL 0.98 // strong damping for stability
#define CHAOTIC_VELOCITY_DAMPING_HIGH   0.95 // high‑speed damping
#define CHAOTIC_HIGH_SPEED_THRESHOLD   0.3   // low threshold for NDC

// Storm physics
#define STORM_ELECTRIC_FORCE          4.0
#define STORM_ELECTRIC_DAMPING         0.2
#define STORM_BASE_TURBULENCE          0.5
#define STORM_VELOCITY_DAMPING        0.98

#define ELECTRIC_HUE_OFFSET_G          2.1
#define ELECTRIC_HUE_OFFSET_B          4.2

// General physics
#define MAX_VELOCITY                  15.0
#define BOUNDARY_BOUNCE_DAMPING       0.90
#define PARTICLE_PULSE_AMPLITUDE      0.1

// Boundary conditions (NDC coordinates: [-1, 1])
#define NDC_MAX_POS                   1.0      // upper bound in NDC
#define NDC_MIN_POS                  -1.0      // lower bound in NDC
#define BOUNDARY_MARGIN               0.02     // safety margin from edges
#define REPULSION_ZONE                0.05     // zone where repulsion activates
#define REPULSION_STRENGTH             2.0     // reduced strength of boundary repulsion

// ---------------------------------------------------------------------------
// Helper constants from Common.h (must be present there)
//   MIN_DT, MAX_DT, DEFAULT_DT, MIN_VECTOR_LENGTH, MAX_FLOAT_VALUE, TWO_PI
// ---------------------------------------------------------------------------

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
    float2 pos   = p.position.xy;
    float2 target = p.targetPosition.xy;
    float2 toTarget = target - pos;
    float  distToTarget = length(toTarget);

    float2 safeScreen = max(params[0].screenSize, float2(1.0));
    float2 pixelToNDC = float2(2.0 / safeScreen.x, 2.0 / safeScreen.y);
    float snapThreshold = min(pixelToNDC.x, pixelToNDC.y) * COLLECTION_SNAP_PIXELS;

    if (distToTarget <= snapThreshold) {
        p.position.xy = target;
        p.velocity.xy = float2(0.0);
        if (p.life >= PARTICLE_ALIVE) {
            p.life = PARTICLE_COLLECTED;
            atomic_fetch_add_explicit(collectedCounter, 1u, memory_order_relaxed);
        }
        return p.velocity.xy;
    }

    float baseSpeedPixels = (params[0].collectionSpeed > 0.0)
        ? params[0].collectionSpeed * COLLECTION_BASE_SPEED
        : COLLECTION_BASE_SPEED;

    float distPixels = distToTarget / max(min(pixelToNDC.x, pixelToNDC.y), 1e-6);
    // Плавное замедление ближе к цели
    float ease = clamp(distPixels / 12.0, 0.1, 1.0);
    float moveDistancePixels = baseSpeedPixels * safeDt * ease;
    float moveDistance = moveDistancePixels * min(pixelToNDC.x, pixelToNDC.y);
    float minMove = min(pixelToNDC.x, pixelToNDC.y) * COLLECTION_MIN_SPEED;
    moveDistance = max(moveDistance, minMove);
    moveDistance = min(moveDistance, distToTarget);

    float2 prevPos = p.position.xy;

    if (distToTarget > snapThreshold) {
        float2 direction = safeNormalize2(toTarget);
        p.position.xy += direction * moveDistance;
    }

    float2 newVelocity = (p.position.xy - prevPos) / safeDt;
    p.velocity.xy = mix(p.velocity.xy, newVelocity, COLLECTION_VELOCITY_DAMPING);

    return p.velocity.xy;
}

// ============================================================================
// CHAOTIC MOVEMENT
// ============================================================================
static inline float2 calculateChaoticMovement(
    thread Particle& p,
    uint id,
    constant SimulationParams * params,
    float safeDt
) {
    float2 chaoticMovement = turbulentMotion(p.position.xy,
                                            params[0].time,
                                            id);

    float2 chaoticDir = safeNormalize2(chaoticMovement);

    float chaoticScale = CHAOTIC_MOVEMENT_SCALE;
    p.velocity.xy += chaoticDir * chaoticScale * safeDt;

    float velocityDamping = CHAOTIC_VELOCITY_DAMPING_NORMAL;
    float speedSq = dot(p.velocity.xy, p.velocity.xy);
    if (speedSq > CHAOTIC_HIGH_SPEED_THRESHOLD * CHAOTIC_HIGH_SPEED_THRESHOLD) {
        velocityDamping = CHAOTIC_VELOCITY_DAMPING_HIGH;
    }
    p.velocity.xy *= velocityDamping;

    return p.velocity.xy;
}

// ============================================================================
// STORM MOVEMENT
// ============================================================================
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
        0.4 + 0.6 * sin(electricHue + ELECTRIC_HUE_OFFSET_G),
        0.8 + 0.2 * sin(electricHue + ELECTRIC_HUE_OFFSET_B),
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
        float pulse = sin(p.life * 2.0 + float(id) * 0.01) *
                     PARTICLE_PULSE_AMPLITUDE + 1.0;
        size = p.baseSize * pulse;
    }

    if (!isFloatSafe(size) || size < 0.0) {
        size = params[0].minParticleSize;
    }

    return clamp(size,
                 params[0].minParticleSize,
                 params[0].maxParticleSize);
}

// ============================================================================
// PHYSICS INTEGRATION
// ============================================================================

static inline void applyBoundaryConditionsForPhysics(
    thread Particle& p,
    constant SimulationParams * params
) {
    if (!isFloatSafe(p.position.x)) p.position.x = 0.0;
    if (!isFloatSafe(p.position.y)) p.position.y = 0.0;

    // Во время сбора не ограничиваем частицы "внутренними" границами,
    // иначе крайние пиксели (близко к NDC ±1.0) никогда не достигаются.
    if (params[0].state == SIMULATION_STATE_COLLECTING ||
        params[0].state == SIMULATION_STATE_COLLECTED) {
        p.position.x = clamp(p.position.x, NDC_MIN_POS, NDC_MAX_POS);
        p.position.y = clamp(p.position.y, NDC_MIN_POS, NDC_MAX_POS);
        if (length(p.velocity.xy) > MAX_VELOCITY) {
            p.velocity.xy = safeNormalize2(p.velocity.xy) * MAX_VELOCITY;
        }
        return;
    }

    float repulsionZoneMin = NDC_MIN_POS + REPULSION_ZONE;  // -0.95
    float repulsionZoneMax = NDC_MAX_POS - REPULSION_ZONE;  //  0.95
    float clampMin = NDC_MIN_POS + BOUNDARY_MARGIN;         // -0.98
    float clampMax = NDC_MAX_POS - BOUNDARY_MARGIN;         //  0.98

    if (p.position.x < repulsionZoneMin) {
        float penetration = repulsionZoneMin - p.position.x;
        p.velocity.x += penetration * REPULSION_STRENGTH * DEFAULT_DT;

        if (p.position.x <= NDC_MIN_POS) {
            p.position.x = clampMin;
            if (p.velocity.x < 0.0) {
                p.velocity.x = -p.velocity.x * BOUNDARY_BOUNCE_DAMPING;
            }
        }
    } else if (p.position.x > repulsionZoneMax) {
        float penetration = p.position.x - repulsionZoneMax;
        p.velocity.x -= penetration * REPULSION_STRENGTH * DEFAULT_DT;

        if (p.position.x >= NDC_MAX_POS) {
            p.position.x = clampMax;
            if (p.velocity.x > 0.0) {
                p.velocity.x = -p.velocity.x * BOUNDARY_BOUNCE_DAMPING;
            }
        }
    }

    if (p.position.y < repulsionZoneMin) {
        float penetration = repulsionZoneMin - p.position.y;
        p.velocity.y += penetration * REPULSION_STRENGTH * DEFAULT_DT;

        if (p.position.y <= NDC_MIN_POS) {
            p.position.y = clampMin;
            if (p.velocity.y < 0.0) {
                p.velocity.y = -p.velocity.y * BOUNDARY_BOUNCE_DAMPING;
            }
        }
    } else if (p.position.y > repulsionZoneMax) {
        float penetration = p.position.y - repulsionZoneMax;
        p.velocity.y -= penetration * REPULSION_STRENGTH * DEFAULT_DT;

        if (p.position.y >= NDC_MAX_POS) {
            p.position.y = clampMax;
            if (p.velocity.y > 0.0) {
                p.velocity.y = -p.velocity.y * BOUNDARY_BOUNCE_DAMPING;
            }
        }
    }

    if (length(p.velocity.xy) > MAX_VELOCITY) {
        p.velocity.xy = safeNormalize2(p.velocity.xy) * MAX_VELOCITY;
    }
}

// ============================================================================
// Integrate position and velocity
// ============================================================================
static inline void integrateParticleForPhysics(
    thread Particle& p,
    float safeDt,
    float2 acceleration
) {
    p.velocity.xy += acceleration * safeDt;

    float speedSq = dot(p.velocity.xy, p.velocity.xy);
    float speed = sqrt(speedSq);
    if (!isFloatSafe(speed)) {
        p.velocity = float3(0.0, 0.0, 0.0);
        speed = 0.0;
    }
    if (speed > MAX_VELOCITY) {
        p.velocity.xy = safeNormalize2(p.velocity.xy) * MAX_VELOCITY;
    }

    float2 oldPos = p.position.xy;
    p.position.xy += p.velocity.xy * safeDt;

    if (!isFloatSafe(p.position.x)) p.position.x = oldPos.x;
    if (!isFloatSafe(p.position.y)) p.position.y = oldPos.y;
}

// ============================================================================
// Pixel-perfect mode (unchanged)
// ============================================================================
static inline void applyPixelPerfectMode(thread Particle& p, uint pixelSizeMode) {
    if (pixelSizeMode == 1) {
        p.position.x = round(p.position.x);
        p.position.y = round(p.position.y);
    }
}

// ============================================================================
// COMPUTE SHADER – PARTICLE PHYSICS UPDATE
// ============================================================================

kernel void updateParticles(
    device Particle*          particles          [[buffer(0)]],
    constant SimulationParams* params           [[buffer(1)]],
    device atomic_uint*       collectedCounter  [[buffer(2)]],
    uint                     thread_position_in_grid [[thread_position_in_grid]]
) {
    uint id = thread_position_in_grid;
    if (id >= params[0].particleCount) return;

    Particle p = particles[id];
    float safeDt = safeDeltaTimeForPhysics(params[0].deltaTime);

    bool isFullyCollected = (p.life == PARTICLE_COLLECTED &&
                             params[0].state == SIMULATION_STATE_COLLECTED);

    if (!isFullyCollected) {
        // Restore original color at the start of each update except storm mode
        if (params[0].state != SIMULATION_STATE_LIGHTNING_STORM) {
            p.color = p.originalColor;
        }
        
        switch (params[0].state) {
            case SIMULATION_STATE_COLLECTING:
                calculateCollectionMovement(p, params, safeDt, collectedCounter);
                break;

            case SIMULATION_STATE_COLLECTED:
                // Жестко фиксируем частицы на цели, чтобы убрать "недосбор"
                p.position.xy = p.targetPosition.xy;
                p.velocity.xy = float2(0.0);
                p.life = PARTICLE_COLLECTED;
                break;

            case SIMULATION_STATE_LIGHTNING_STORM:
                calculateStormMovement(p, id, params);
                break;

            case SIMULATION_STATE_IDLE:
            case SIMULATION_STATE_CHAOTIC:
            default:
                calculateChaoticMovement(p, id, params, safeDt);
                break;
        }

        integrateParticleForPhysics(p, safeDt, float2(0.0));
        applyBoundaryConditionsForPhysics(p, params);
        p.size = calculateParticleSize(p, params, id);

        if (isFloatSafe(p.life) && p.life >= PARTICLE_ALIVE) {
            p.life += safeDt;
            if (p.life > TWO_PI) {
                p.life -= TWO_PI;
            }
        }
    }

    particles[id] = p;
}

#endif /* Physics_h */
