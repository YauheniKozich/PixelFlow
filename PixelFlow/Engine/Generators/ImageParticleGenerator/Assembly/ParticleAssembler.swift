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
import UIKit
import simd
import CoreGraphics

final class DefaultParticleAssembler: ParticleAssembler, ParticleAssemblerProtocol {

    private let config: ParticleGenerationConfig
    private let randomGenerator = SystemRandomNumberGenerator()

    // MARK: - ParticleAssemblerProtocol

    var defaultParticleSize: Float { 5.0 }

    init(config: ParticleGenerationConfig) {
        self.config = config
        print("DefaultParticleAssembler инициализирован")
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
        
        // Генерация частиц
        let particles = samples.enumerated().map { index, sample -> Particle in
            createParticle(
                from: sample,
                index: index,
                transformation: transformation,
                sizeRange: sizeRange,
                sizeVariation: sizeVariation,
                config: config,
                displayMode: displayMode,
                totalSamples: samples.count,
                originalImageSize: originalImageSize,
                scaledImageSize: imageSize,
                screenSize: screenSize
            )
        }
        
        Logger.shared.debug("Сборка частиц завершена: \(particles.count) частиц")
        return particles
    }
    
    // MARK: - Private Methods
    
    /// Получаем режим отображения из конфигурации
    private func getDisplayMode(from config: ParticleGenerationConfig) -> ImageDisplayMode {
        // Если протокол поддерживает свойство imageDisplayMode
        if let configWithDisplayMode = config as? ParticleGeneratorConfigurationWithDisplayMode {
            return configWithDisplayMode.imageDisplayMode
        }
        
        // Проверяем наличие свойства через Mirror
        if let displayModeValue = Mirror(reflecting: config).children.first(where: { $0.label == "imageDisplayMode" })?.value as? ImageDisplayMode {
            return displayModeValue
        }
        
        // Значение по умолчанию
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
        displayMode: ImageDisplayMode,
        totalSamples: Int,
        originalImageSize: CGSize,
        scaledImageSize: CGSize,
        screenSize: CGSize
    ) -> Particle {
        
        var particle = Particle()
        
        // Нормализуем координаты внутри оригинального изображения
        let normalizedX = CGFloat(sample.x) / originalImageSize.width
        let normalizedY = CGFloat(sample.y) / originalImageSize.height
        
        // Применяем формулу трансформации
        let screenX = transformation.offset.x +
        normalizedX * scaledImageSize.width * transformation.scaleX
        let screenY = transformation.offset.y +
        normalizedY * scaledImageSize.height * transformation.scaleY
        
        // Граничная валидация
        guard screenX >= -50 && screenX <= screenSize.width + 50,
              screenY >= -50 && screenY <= screenSize.height + 50 else {
            return Particle()
        }
        
        // Заполняем параметры частицы
        particle.position = SIMD3<Float>(Float(screenX), Float(screenY), 0)
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
        
        let chaosFactor = Float.random(in: 0.8...1.2)
        particle.idleChaoticMotion = 0
        particle.velocity = SIMD3<Float>(
            Float.random(in: -0.5...0.5),
            Float.random(in: -0.5...0.5),
            0
        ) * getParticleSpeed(from: config) * chaosFactor
        
        return particle
    }
    
    private func getSizeRange(for preset: QualityPreset) -> ClosedRange<Float> {
        // Стандартные диапазоны по умолчанию
        let defaultRanges: [QualityPreset: ClosedRange<Float>] = [
            .ultra: 0.8...15.0,
            .high: 1.5...12.0,
            .standard: 2.0...9.0,
            .draft: 3.0...7.0
        ]
        
        // Пробуем получить кастомные значения через Mirror
        if let sizeRange: ClosedRange<Float> = getCustomProperty(named: "particleSize\(preset)", from: config) {
            return sizeRange
        }
        
        // Возвращаем значения по умолчанию
        return defaultRanges[preset] ?? 2.0...8.0
    }
    
    /// Получение времени жизни частицы
    private func getParticleLifetime(from config: ParticleGenerationConfig) -> Float {
        if let lifetime: Float = getCustomProperty(named: "particleLifetime", from: config) {
            return lifetime
        }
        return 5.0 // Значение по умолчанию
    }
    
    /// Получение скорости частицы
    private func getParticleSpeed(from config: ParticleGenerationConfig) -> Float {
        if let speed: Float = getCustomProperty(named: "particleSpeed", from: config) {
            return speed
        }
        return 1.0 // Значение по умолчанию
    }
    
    /// Получение кастомного свойства через reflection
    private func getCustomProperty<T>(named name: String, from config: ParticleGenerationConfig) -> T? {
        let mirror = Mirror(reflecting: config)
        for child in mirror.children {
            if child.label == name {
                return child.value as? T
            }
        }
        return nil
    }

    // MARK: - ParticleAssemblerProtocol

    func validateParticles(_ particles: [Particle]) -> Bool {
        // Простая валидация: все частицы должны иметь валидные позиции и размеры
        return particles.allSatisfy { particle in
            particle.size > 0 &&
            particle.position.x.isFinite && particle.position.y.isFinite && particle.position.z.isFinite
        }
    }
}
