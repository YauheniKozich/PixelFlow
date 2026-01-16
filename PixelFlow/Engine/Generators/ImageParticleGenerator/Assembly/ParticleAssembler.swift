//
//  ParticleAssembler.swift
//  PixelFlow
//
//  Компонент для сборки частиц из сэмплов пикселей
//  - Преобразование сэмплов в структуры Particle
//  - Масштабирование под экран
//  - Настройка цветов и размеров
//

import Foundation
import simd
import CoreGraphics

final class DefaultParticleAssembler: ParticleAssembler, ParticleAssemblerProtocol {
    
    
    private let config: ParticleGenerationConfig
    
    init(config: ParticleGenerationConfig) {
        self.config = config
    }
    
    func assembleParticles(
        from samples: [Sample],
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        imageSize: CGSize,
        originalImageSize: CGSize
    ) -> [Particle] {
        
        return assembleParticlesOriginal(
            from: samples,
            config: config,
            screenSize: screenSize,
            imageSize: imageSize,
            originalImageSize: originalImageSize
        )
    }
    
    // MARK: - Оригинальная функция
    
    private func assembleParticlesOriginal(
        from samples: [Sample],
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        imageSize: CGSize,
        originalImageSize: CGSize
    ) -> [Particle] {
        
        // Валидация входных данных
        guard !samples.isEmpty else {
            Logger.shared.warning("Не предоставлены сэмплы для сборки частиц")
            return []
        }
        
        guard imageSize.width > 0, imageSize.height > 0 else {
            Logger.shared.error("Неверный размер изображения: \(imageSize)")
            return []
        }
        
        guard screenSize.width > 0, screenSize.height > 0 else {
            Logger.shared.error("Неверный размер экрана: \(screenSize)")
            return []
        }
        
        // Получаем режим отображения
        let displayMode = getDisplayMode(from: config)
        
        // Предварительный расчет параметров трансформации
        let transformation = calculateTransformation(
            screenSize: screenSize,
            imageSize: imageSize,
            displayMode: displayMode
        )
        
        // Подготовка диапазона размеров
        let sizeRange = getSizeRange(for: config.qualityPreset)
        let sizeVariation = sizeRange.upperBound - sizeRange.lowerBound
        
        // Генерация частиц (оптимизировано)
        var particles: [Particle] = []
        particles.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            particles.append(
                createParticle(
                    from: sample,
                    index: index,
                    transformation: transformation,
                    sizeRange: sizeRange,
                    sizeVariation: sizeVariation,
                    config: config,
                    totalSamples: samples.count,
                    originalImageSize: originalImageSize,
                    screenSize: screenSize
                )
            )
        }
        
        Logger.shared.debug("Сборка частиц завершена: \(particles.count) частиц")
        
        // Логирование первых 10 частиц для отладки
        if particles.count >= 10 {
            Logger.shared.debug("Первые 10 частиц:")
            for i in 0..<10 {
                let p = particles[i]
                Logger.shared.debug("  [\(i)] pos=(\(p.position.x), \(p.position.y)) color=(\(p.color.x), \(p.color.y), \(p.color.z), \(p.color.w)) size=\(p.size)")
            }
        }
        
        return particles
    }
    
    // MARK: - Private Methods
    
    /// Получаем режим отображения из конфигурации
    private func getDisplayMode(from config: ParticleGenerationConfig) -> ImageDisplayMode {
        if let configWithDisplayMode = config as? ParticleGeneratorConfigurationWithDisplayMode {
            return configWithDisplayMode.imageDisplayMode
        }
        return .fit
    }
    
    /// Расчет параметров трансформации координат
    private func calculateTransformation(
        screenSize: CGSize,
        imageSize: CGSize,
        displayMode: ImageDisplayMode
    ) -> TransformationParams {
        
        let aspectImage  = imageSize.width / imageSize.height
        let aspectScreen = screenSize.width / screenSize.height
        
        switch displayMode {
        case .fit:
            let scale: CGFloat = (aspectImage > aspectScreen)
            ? screenSize.width / imageSize.width
            : screenSize.height / imageSize.height
            
            let scaledWidth  = imageSize.width  * scale
            let scaledHeight = imageSize.height * scale
            let offset = CGPoint(
                x: (screenSize.width  - scaledWidth)  / 2,
                y: (screenSize.height - scaledHeight) / 2
            )
            return TransformationParams(scaleX: scale,
                                        scaleY: scale,
                                        offset: offset,
                                        mode: .fit)
            
        case .fill:
            let scale: CGFloat = (aspectImage > aspectScreen)
            ? screenSize.height / imageSize.height
            : screenSize.width  / imageSize.width
            
            let scaledWidth  = imageSize.width  * scale
            let scaledHeight = imageSize.height * scale
            let offset = CGPoint(
                x: (screenSize.width  - scaledWidth)  / 2,
                y: (screenSize.height - scaledHeight) / 2
            )
            
            return TransformationParams(scaleX: scale,
                                        scaleY: scale,
                                        offset: offset,
                                        mode: .fill)
            
        case .stretch:
            let scaleX = screenSize.width  / imageSize.width
            let scaleY = screenSize.height / imageSize.height
            return TransformationParams(scaleX: scaleX,
                                        scaleY: scaleY,
                                        offset: .zero,
                                        mode: .stretch)
            
        case .center:
            let offset = CGPoint(
                x: (screenSize.width  - imageSize.width)  / 2,
                y: (screenSize.height - imageSize.height) / 2
            )
            return TransformationParams(scaleX: 1.0,
                                        scaleY: 1.0,
                                        offset: offset,
                                        mode: .center)
        }
    }
    
    /// Создание отдельной частицы
    private func createParticle(
        from sample: Sample,
        index: Int,
        transformation: TransformationParams,
        sizeRange: ClosedRange<Float>,
        sizeVariation: Float,
        config: ParticleGenerationConfig,
        totalSamples: Int,
        originalImageSize: CGSize,
        screenSize: CGSize
    ) -> Particle {
        
        var particle = Particle()
        
        // Защита от некорректных размеров
        guard originalImageSize.width > 0, originalImageSize.height > 0 else {
            return particle
        }
        
        // Координаты в пространстве изображения
        let imageX = CGFloat(sample.x)
        let imageY = CGFloat(sample.y)
        
        // Применяем масштаб и смещение (в экранных координатах)
        let screenX = transformation.offset.x + imageX * transformation.scaleX
        let screenY = transformation.offset.y + imageY * transformation.scaleY

        // Нормализация в диапазон 0…1
        let nx = screenSize.width > 0 ? screenX / screenSize.width : 0
        let ny = screenSize.height > 0 ? screenY / screenSize.height : 0

        // Жёсткий clamp уже в нормализованном пространстве
        let clampedNX = min(max(nx, 0), 1)
        let clampedNY = min(max(ny, 0), 1)

        particle.position = SIMD3<Float>(Float(clampedNX), Float(clampedNY), 0)
        particle.targetPosition = particle.position
        particle.color = sample.color
        particle.originalColor = sample.color
        
        // Размер
        let xHash = UInt32(sample.x) &* 73856093
        let yHash = UInt32(sample.y) &* 19349663
        let combinedHash = Int32(bitPattern: xHash ^ yHash)
        let positionFactor = Float(abs(combinedHash) % 1000) / 1000.0
        let indexFactor = Float(index) / Float(max(totalSamples, 1))
        let sizeFactor = (positionFactor + indexFactor) / 2.0
        particle.size = sizeRange.lowerBound + sizeFactor * sizeVariation
        particle.baseSize = particle.size
        
        // Жизненный цикл и движение
        particle.life = 0.0
        
        // Быстрый PRNG на основе sample координат и индекса
        var seed = UInt32(sample.x) &* 73856093 ^ UInt32(sample.y) &* 19349663 ^ UInt32(index)
        func xorshift32(_ value: inout UInt32) -> UInt32 {
            var x = value
            x ^= x << 13
            x ^= x >> 17
            x ^= x << 5
            value = x
            return x
        }
        
        // Используем PRNG для скорости и хаоса
        let chaosFactor = 0.8 + Float(xorshift32(&seed) % 400) / 1000.0
        let vx = -0.5 + Float(xorshift32(&seed) % 1000) / 1000.0
        let vy = -0.5 + Float(xorshift32(&seed) % 1000) / 1000.0
        
        particle.idleChaoticMotion = 0
        particle.velocity = SIMD3<Float>(vx, vy, 0) * getParticleSpeed(from: config) * chaosFactor
        
        return particle
    }
    
    private func getSizeRange(for preset: QualityPreset) -> ClosedRange<Float> {
        if let configWithDisplayMode = config as? ParticleGeneratorConfigurationWithDisplayMode {
            switch preset {
            case .ultra:
                return configWithDisplayMode.particleSizeUltra ?? 0.8...15.0
            case .high:
                return configWithDisplayMode.particleSizeHigh ?? 1.5...12.0
            case .standard:
                return configWithDisplayMode.particleSizeStandard ?? 2.0...9.0
            case .draft:
                return configWithDisplayMode.particleSizeLow ?? 3.0...7.0
            }
        }
        
        // Значения по умолчанию
        let defaultRanges: [QualityPreset: ClosedRange<Float>] = [
            .ultra: 0.8...15.0,
            .high: 1.5...12.0,
            .standard: 2.0...9.0,
            .draft: 3.0...7.0
        ]
        return defaultRanges[preset] ?? 2.0...8.0
    }
    
    /// Получение скорости частицы
    private func getParticleSpeed(from config: ParticleGenerationConfig) -> Float {
        if let configWithDisplayMode = config as? ParticleGeneratorConfigurationWithDisplayMode {
            return configWithDisplayMode.particleSpeed
        }
        return 1.0
    }
}
