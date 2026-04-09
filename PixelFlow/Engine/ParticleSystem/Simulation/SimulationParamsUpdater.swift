//
//  SimulationParamsUpdater.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit

final class SimulationParamsUpdater {
    
// swiftlint:disable:next function_parameter_count
    func fill(
        buffer: MTLBuffer,
        state: SimulationState,
        clock: SimulationClockProtocol,
        screenSize: CGSize,
        particleCount: Int,
        config: ParticleGenerationConfig,
        enableIdleChaotic: Bool = false,
        displayScale: Float = 1.0,
        collectionSpeed: Float = 8.0,
        brightnessBoost: Float = 2.0,
        threadsPerThreadgroup: UInt32 = 256
    ) {
        guard buffer.length >= MemoryLayout<SimulationParams>.stride else {
            assertionFailure("Buffer is too small for SimulationParams")
            return
        }

        var params = SimulationParams()

        // Основные параметры симуляции
        params.time = clock.time
        params.deltaTime = clock.deltaTime
        params.particleCount = UInt32(particleCount)

        // Валидация размеров экрана
        let safeWidth = max(Float(screenSize.width), 1.0)
        let safeHeight = max(Float(screenSize.height), 1.0)
        params.screenSize = .init(safeWidth, safeHeight)
        params.state = state.shaderValue

        // Параметры рендеринга частиц
        // Использовать значения по умолчанию из инициализации структуры (minParticleSize: 1.0, maxParticleSize: 6.0)
        // Они используются шейдерами для ограничения размеров частиц
        // swiftlint:disable:next todo
        // TODO: Рассмотреть возможность настройки через ParticleSystem API
        let minSize = max(Float(config.minParticleSize) * displayScale, 0.5)
        let maxSize = max(Float(config.maxParticleSize) * displayScale, minSize)
        params.minParticleSize = minSize
        params.maxParticleSize = maxSize

        // Параметры анимации и эффектов
        params.collectionSpeed = collectionSpeed  // Множитель скорости сбора
        params.brightnessBoost = brightnessBoost  // Увеличение яркости по умолчанию (используется фрагментным шейдером)
        // 0 = плавный (с субпиксельным джиттером)
        // 1 = пиксельно-точный (снап к пиксельной сетке, если будет включен)
        // 2 = full-res квадраты без джиттера (для 1:1 пиксельной сетки изображения)
        // Фиксируем pixelSizeMode=2 для всех режимов, чтобы исключить субпиксельные отличия
        params.pixelSizeMode = 2
        params.colorsLocked = 0       // 0 = шейдеры могут изменять цвета, 1 = заблокировано на оригинальные

        // ПОДДЕРЖКА ХАОТИЧНОГО ДВИЖЕНИЯ В IDLE
        if case .idle = state, enableIdleChaotic {
            params.idleChaoticMotion = 1 // Enabled
        } else {
            params.idleChaoticMotion = 0 // Disabled
        }

        // РАЗМЕР THREADGROUP ДЛЯ COMPUTE SHADER
        params.threadsPerThreadgroup = threadsPerThreadgroup

        buffer.contents()
            .assumingMemoryBound(to: SimulationParams.self)
            .pointee = params
    }
}
