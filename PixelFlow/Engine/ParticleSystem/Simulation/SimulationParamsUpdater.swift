//
//  SimulationParamsUpdater.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit

final class SimulationParamsUpdater {
    
    func fill(
        buffer: MTLBuffer,
        state: SimulationState,
        clock: SimulationClockProtocol,
        screenSize: CGSize,
        particleCount: Int,
        config: ParticleGenerationConfig,
        enableIdleChaotic: Bool = false,
        displayScale: Float = 1.0,
        collectionSpeed: Float = 5.0,
        brightnessBoost: Float = 2.0,
        threadsPerThreadgroup: UInt32 = 256
    ) {
        guard buffer.length >= MemoryLayout<SimulationParams>.stride else {
            assertionFailure("Buffer is too small for SimulationParams")
            return
        }
        
        var p = SimulationParams()
        
        // === Основные параметры симуляции ===
        p.time = clock.time
        p.deltaTime = clock.deltaTime
        p.particleCount = UInt32(particleCount)
        
        // Валидация размеров экрана
        let safeWidth = max(Float(screenSize.width), 1.0)
        let safeHeight = max(Float(screenSize.height), 1.0)
        p.screenSize = .init(safeWidth, safeHeight)
        p.state = state.shaderValue
        
        // === Параметры рендеринга частиц ===
        // Использовать значения по умолчанию из инициализации структуры (minParticleSize: 1.0, maxParticleSize: 6.0)
        // Они используются шейдерами для ограничения размеров частиц
        // TODO: Рассмотреть возможность настройки через ParticleSystem API
        let minSize = max(Float(config.minParticleSize) * displayScale, 0.5)
        let maxSize = max(Float(config.maxParticleSize) * displayScale, minSize)
        p.minParticleSize = minSize
        p.maxParticleSize = maxSize

        
        // === Параметры анимации и эффектов ===
        p.collectionSpeed = collectionSpeed  // Множитель скорости сбора
        p.brightnessBoost = brightnessBoost  // Увеличение яркости по умолчанию (используется фрагментным шейдером)
        p.pixelSizeMode = 0      // 0 = плавный, 1 = пиксельно-точный (используется вершинным шейдером)
        p.colorsLocked = 0       // 0 = шейдеры могут изменять цвета, 1 = заблокировано на оригинальные
        
        // === ПОДДЕРЖКА ХАОТИЧНОГО ДВИЖЕНИЯ В IDLE ===
        if case .idle = state, enableIdleChaotic {
            p.idleChaoticMotion = 1 // Enabled
        } else {
            p.idleChaoticMotion = 0 // Disabled
        }

        // === РАЗМЕР THREADGROUP ДЛЯ COMPUTE SHADER ===
        p.threadsPerThreadgroup = threadsPerThreadgroup
        
        buffer.contents()
            .assumingMemoryBound(to: SimulationParams.self)
            .pointee = p
    }
}
