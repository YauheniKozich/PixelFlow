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
        enableIdleChaotic: Bool = false
    ) {
        var p = SimulationParams()
        
        // === Основные параметры симуляции ===
        p.time = clock.time
        p.deltaTime = clock.deltaTime
        p.particleCount = UInt32(particleCount)
        p.screenSize = .init(Float(screenSize.width), Float(screenSize.height))
        p.state = state.shaderValue
        
        // === Параметры рендеринга частиц ===
        // Использовать значения по умолчанию из инициализации структуры (minParticleSize: 1.0, maxParticleSize: 6.0)
        // Они используются шейдерами для ограничения размеров частиц
        // TODO: Рассмотреть возможность настройки через ParticleSystem API
         p.minParticleSize = config.minParticleSize
         p.maxParticleSize = config.maxParticleSize

        
        // === Параметры анимации и эффектов ===
        p.collectionSpeed = 5.0  // Множитель скорости сбора
        p.brightnessBoost = 0.8  // Увеличение яркости по умолчанию (используется фрагментным шейдером)
        p.pixelSizeMode = 0      // 0 = плавный, 1 = пиксельно-точный (используется вершинным шейдером)
        p.colorsLocked = 0       // 0 = шейдеры могут изменять цвета, 1 = заблокировано на оригинальные
        
        // === ПОДДЕРЖКА ХАОТИЧНОГО ДВИЖЕНИЯ В IDLE ===
        if case .idle = state, enableIdleChaotic {
            p.idleChaoticMotion = 1 // Enabled
        } else {
            p.idleChaoticMotion = 0 // Disabled
        }
        
        buffer.contents()
            .assumingMemoryBound(to: SimulationParams.self)
            .pointee = p
    }
}
