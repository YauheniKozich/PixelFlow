//
//  Particle.swift
//  PixelFlow
//

import simd

// КРИТИЧНО: Должен точно соответствовать Particle в Common.h (Shaders/Core/Common.h) по порядку полей, типам и выравниванию
// Изменение порядка полей или типов приведет к неопределенному поведению при доступе к GPU памяти
struct Particle: Codable {
    // Данные позиции (выровнены до 16 байт для SIMD)
    var position: SIMD3<Float>        // float3 - 12 bytes + 4 padding = 16
    var velocity: SIMD3<Float>        // float3 - 12 bytes + 4 padding = 16
    var targetPosition: SIMD3<Float>  // float3 - 12 bytes + 4 padding = 16

    // Данные цвета (выровнены до 16 байт)
    var color: SIMD4<Float>           // float4 - 16 bytes
    var originalColor: SIMD4<Float>   // float4 - 16 bytes

    // Данные размера (упакованные float)
    var size: Float                   // float - 4 bytes
    var baseSize: Float               // float - базовый размер для пульсации - 4 bytes
    var life: Float                   // float - 4 bytes
    var idleChaoticMotion: UInt32 = 0 // uint - 4 bytes - флаг для хаотичного движения в idle

    // Общий размер ожидается: ~80 байт с правильным выравниванием

    init() {
        self.position = .zero
        self.velocity = .zero
        self.targetPosition = .zero
        self.color = SIMD4<Float>(1, 1, 1, 1)
        self.size = 2.0
        self.baseSize = 2.0
        self.life = 0.0
        self.idleChaoticMotion = 0
        self.originalColor = SIMD4<Float>(1, 1, 1, 1)
    }

    // MARK: - Codable Implementation

    enum CodingKeys: String, CodingKey {
        case position, velocity, targetPosition, color, originalColor
        case size, baseSize, life, idleChaoticMotion
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)

        // Decode SIMD3 as arrays
        let positionArray = try container.decode([Float].self, forKey: .position)
        position = SIMD3<Float>(positionArray[0], positionArray[1], positionArray[2])

        let velocityArray = try container.decode([Float].self, forKey: .velocity)
        velocity = SIMD3<Float>(velocityArray[0], velocityArray[1], velocityArray[2])

        let targetPositionArray = try container.decode([Float].self, forKey: .targetPosition)
        targetPosition = SIMD3<Float>(targetPositionArray[0], targetPositionArray[1], targetPositionArray[2])

        // Decode SIMD4 as arrays
        let colorArray = try container.decode([Float].self, forKey: .color)
        color = SIMD4<Float>(colorArray[0], colorArray[1], colorArray[2], colorArray[3])

        let originalColorArray = try container.decode([Float].self, forKey: .originalColor)
        originalColor = SIMD4<Float>(originalColorArray[0], originalColorArray[1], originalColorArray[2], originalColorArray[3])

        // Decode simple types
        size = try container.decode(Float.self, forKey: .size)
        baseSize = try container.decode(Float.self, forKey: .baseSize)
        life = try container.decode(Float.self, forKey: .life)
        idleChaoticMotion = try container.decode(UInt32.self, forKey: .idleChaoticMotion)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)

        // Encode SIMD3 as arrays
        try container.encode([position.x, position.y, position.z], forKey: .position)
        try container.encode([velocity.x, velocity.y, velocity.z], forKey: .velocity)
        try container.encode([targetPosition.x, targetPosition.y, targetPosition.z], forKey: .targetPosition)

        // Encode SIMD4 as arrays
        try container.encode([color.x, color.y, color.z, color.w], forKey: .color)
        try container.encode([originalColor.x, originalColor.y, originalColor.z, originalColor.w], forKey: .originalColor)

        // Encode simple types
        try container.encode(size, forKey: .size)
        try container.encode(baseSize, forKey: .baseSize)
        try container.encode(life, forKey: .life)
        try container.encode(idleChaoticMotion, forKey: .idleChaoticMotion)
    }
}

// КРИТИЧНО: Должен точно соответствовать SimulationParams в Common.h (Shaders/Core/Common.h) по порядку полей, типам и выравниванию
// Общий размер ДОЛЖЕН быть точно 256 байт для выравнивания Metal буфера - НЕ МЕНЯЙТЕ ПОРЯДОК ПОЛЕЙ ИЛИ ТИПЫ
struct SimulationParams {
    // ---- 0 .. 15 (скаляры)
    var state: UInt32 = 0                    // 4
    var pixelSizeMode: UInt32 = 0            // 4
    var colorsLocked: UInt32 = 0             // 4 - предотвращает изменение цветов шейдером
    var _pad1: UInt32 = 0                     // 4

    // ---- 16 .. 31 (float)
    var deltaTime: Float = 0                  // 4
    var collectionSpeed: Float = 0            // 4
    var brightnessBoost: Float = 1            // 4
    var _pad2: Float = 0                       // 4

    // ---- 32 .. 47 (SIMD2)
    var screenSize: SIMD2<Float> = .zero      // 8
    var _pad3: SIMD2<Float> = .zero            // 8

    // ---- 48 .. 63 (критические параметры шейдера)
    var minParticleSize: Float = 1            // 4 - USED by shader
    var maxParticleSize: Float = 6            // 4 - USED by shader
    var time: Float = 0                       // 4 - USED by shader
    var particleCount: UInt32 = 0             // 4 - USED by shader
    var idleChaoticMotion: UInt32 = 0         // 4 - флаг для хаотичного движения в idle
    var padding: UInt32 = 0         // Добавляем для выравнивания
    // ---- 64 .. 255 (padding для достижения 256 байт)
    // Разбивка структуры:
    // - uint fields (0-15): 4*4 = 16 bytes
    // - float fields (16-31): 4*4 = 16 bytes
    // - float2 fields (32-47): 2*8 = 16 bytes
    // - particle params (48-63): 6 fields = 24 bytes (4 float + 2 uint)
    // - reserved array (64-239): 11*16 = 176 bytes
    // - padding (240-255): 8 bytes to align to 256
    // Total: 16+16+16+24+176+8 = 256 bytes exactly
    var _reserved: (
           SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
           SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
           SIMD4<Float>, SIMD4<Float>, SIMD4<Float>,
           SIMD4<Float>, SIMD4<Float>
       ) = (
           .zero, .zero, .zero,
           .zero, .zero, .zero,
           .zero, .zero, .zero,
           .zero, .zero
       )
    // Общий размер: 256 байт (проверяется assert в ParticleSystem+MetalSetup.swift)
}
