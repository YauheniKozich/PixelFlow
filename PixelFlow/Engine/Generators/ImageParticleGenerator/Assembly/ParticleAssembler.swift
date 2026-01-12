//
//  ParticleAssembler.swift
//  PixelFlow
//
//  Компонент для сборки частиц из сэмплов пикселей
//  - Преобразование сэмплов в структуры Particle
//  - Масштабирование под экран
//  - Настройка цветов и размеров
//

import CoreGraphics
import Foundation
import simd


/// Реализация сборщика частиц по умолчанию
final class DefaultParticleAssembler: ParticleAssembler {
    
    private let config: ParticleGeneratorConfiguration
    private let randomGenerator = SystemRandomNumberGenerator()
    
    init(config: ParticleGeneratorConfiguration) {
        self.config = config
    }
    
    func assembleParticles(
        from samples: [Sample],
        config: ParticleGeneratorConfiguration,
        screenSize: CGSize,
        imageSize: CGSize
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
        
        Logger.shared.debug("""
            Сборка \(samples.count) частиц для:
            - Экран: \(screenSize)
            - Изображение: \(imageSize)
            - Качество: \(config.qualityPreset)
        """)
        
        // Получаем режим отображения (используем по умолчанию .fit если не задан)
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
                imageSize: imageSize,
                screenSize: screenSize
            )
        }
        
        Logger.shared.debug("Сборка частиц завершена: \(particles.count) частиц")
        return particles
    }
    
    // MARK: - Private Methods
    
    /// Получаем режим отображения из конфигурации
    private func getDisplayMode(from config: ParticleGeneratorConfiguration) -> ImageDisplayMode {
        // Если протокол поддерживает свойство imageDisplayMode
        if let configWithDisplayMode = config as? ParticleGeneratorConfigurationWithDisplayMode {
            return configWithDisplayMode.imageDisplayMode
        }
        
        // Проверяем наличие свойства через KVC (опционально)
        if let displayModeValue = Mirror(reflecting: config).children.first(where: { $0.label == "imageDisplayMode" })?.value as? ImageDisplayMode {
            return displayModeValue
        }
        
        // Значение по умолчанию
        return .fit
    }
    
    /// Расчет параметров трансформации координат
    // MARK: - Transformation calculation
    private func calculateTransformation(
        screenSize: CGSize,
        imageSize: CGSize,
        displayMode: ImageDisplayMode
    ) -> TransformationParams {

        let aspectImage  = imageSize.width / imageSize.height
        let aspectScreen = screenSize.width / screenSize.height

        switch displayMode {
        case .fit:
            // --- Уже работает правильно (см. ниже) ---
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
            // ----- ОТЛИЧНАЯ РЕАЛИЗАЦИЯ ДЛЯ .fill -----
            // Выбираем коэффициент, который заставит изображение покрыть **обе** оси
            //    (одна из сторон будет «выдавлен» за границы).
            let scale: CGFloat = (aspectImage > aspectScreen)
                ? screenSize.height / imageSize.height      // ограничиваем по высоте
                : screenSize.width  / imageSize.width       // ограничиваем по ширине

            // Масштабируем исходный размер
            let scaledWidth  = imageSize.width  * scale
            let scaledHeight = imageSize.height * scale

            // Смещение (может быть отрицательным)
            let offset = CGPoint(
                x: (screenSize.width  - scaledWidth)  / 2,
                y: (screenSize.height - scaledHeight) / 2
            )

            // Возвращаем **коэффициенты** (не размеры!)
            return TransformationParams(scaleX: scale,
                                        scaleY: scale,
                                        offset: offset,
                                        mode: .fill)

        case .stretch:
            // --- Каждый размер масштабируется независимо ---
            let scaleX = screenSize.width  / imageSize.width
            let scaleY = screenSize.height / imageSize.height
            return TransformationParams(scaleX: scaleX,
                                        scaleY: scaleY,
                                        offset: .zero,
                                        mode: .stretch)

        case .center:
            // --- Без масштабирования, только центрирование ---
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
        config: ParticleGeneratorConfiguration,
        displayMode: ImageDisplayMode,
        totalSamples: Int,
        imageSize: CGSize,
        screenSize: CGSize
    ) -> Particle {

        var particle = Particle()

        // -------------------------------------------------
        // Нормализуем координаты внутри оригинального изображения
        // -------------------------------------------------
        let normalizedX = CGFloat(sample.x) / imageSize.width
        let normalizedY = CGFloat(sample.y) / imageSize.height

        // -------------------------------------------------
        // Применяем единый формулы:
        //    screen = offset + (normalized * imageSize * scale)
        // -------------------------------------------------
        let screenX = transformation.offset.x +
                      normalizedX * imageSize.width  * transformation.scaleX
        let screenY = transformation.offset.y +
                      normalizedY * imageSize.height * transformation.scaleY

        // -------------------------------------------------
        // Граничная валидация (остается неизменной)
        // -------------------------------------------------
        guard screenX >= -50 && screenX <= screenSize.width + 50,
              screenY >= -50 && screenY <= screenSize.height + 50 else {
            // Частица будет отфильтрована дальше
            return Particle()
        }

        // -------------------------------------------------
        // Заполняем остальные параметры частицы
        // -------------------------------------------------
        particle.position = SIMD3<Float>(Float(screenX), Float(screenY), 0)
        particle.targetPosition = particle.position
        particle.color = sample.color
        particle.originalColor = sample.color

        // Размер: используем комбинацию позиции и индекса для разнообразия
        // Улучшенная формула для более равномерного распределения размеров
        // Используем хэш позиции для детерминированного, но разнообразного результата
        let xHash = UInt32(sample.x) &* 73856093
        let yHash = UInt32(sample.y) &* 19349663
        let combinedHash = Int32(bitPattern: xHash ^ yHash)
        let positionFactor = Float(abs(combinedHash) % 1000) / 1000.0
        let indexFactor = Float(index) / Float(max(totalSamples, 1))
        let sizeFactor = (positionFactor + indexFactor) / 2.0
        particle.size = sizeRange.lowerBound + sizeFactor * sizeVariation
        particle.baseSize = particle.size

        // Жизненный цикл и движение – без изменений
        particle.life = 0.0

        let chaosFactor = Float.random(in: 0.8...1.2)
        // idleChaoticMotion должен быть 0 или 1 (флаг), не случайное значение
        particle.idleChaoticMotion = 0
        particle.velocity = SIMD3<Float>(
            Float.random(in: -0.5...0.5),
            Float.random(in: -0.5...0.5),
            0
        ) * getParticleSpeed(from: config) * chaosFactor

        return particle
    }

    
    /// Получение диапазона размеров для пресета качества
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
    private func getParticleLifetime(from config: ParticleGeneratorConfiguration) -> Float {
        if let lifetime: Float = getCustomProperty(named: "particleLifetime", from: config) {
            return lifetime
        }
        return 5.0 // Значение по умолчанию
    }
    
    /// Получение скорости частицы
    private func getParticleSpeed(from config: ParticleGeneratorConfiguration) -> Float {
        if let speed: Float = getCustomProperty(named: "particleSpeed", from: config) {
            return speed
        }
        return 1.0 // Значение по умолчанию
    }
    
    /// Получение кастомного свойства через reflection
    private func getCustomProperty<T>(named name: String, from config: ParticleGeneratorConfiguration) -> T? {
        let mirror = Mirror(reflecting: config)
        for child in mirror.children {
            if child.label == name {
                return child.value as? T
            }
        }
        return nil
    }
    
}

// MARK: - Supporting Structures

private struct TransformationParams {
    let scaleX: CGFloat
    let scaleY: CGFloat
    let offset: CGPoint
    let mode: ImageDisplayMode
}

enum ImageDisplayMode: String, CaseIterable {
    case fit      // Сохранять пропорции, вписывать в экран
    case fill     // Сохранять пропорции, заполнять экран (обрезать)
    case stretch  // Растягивать без сохранения пропорций
    case center   // Центрировать без масштабирования
    
    var description: String {
        switch self {
        case .fit: return "Fit (сохранить пропорции)"
        case .fill: return "Fill (заполнить экран)"
        case .stretch: return "Stretch (растянуть)"
        case .center: return "Center (центрировать)"
        }
    }
}



// MARK: - Протокол для конфигурации с режимом отображения

protocol ParticleGeneratorConfigurationWithDisplayMode: ParticleGeneratorConfiguration {
    var imageDisplayMode: ImageDisplayMode { get }
    var particleLifetime: Float { get }
    var particleSpeed: Float { get }
    var particleSizeUltra: ClosedRange<Float>? { get }
    var particleSizeHigh: ClosedRange<Float>? { get }
    var particleSizeStandard: ClosedRange<Float>? { get }
    var particleSizeLow: ClosedRange<Float>? { get }
}

// MARK: - Расширение для Sample

extension Sample {
    /// Размеры исходного изображения из сэмпла
    var imageWidth: Int {
        // Если в Sample нет информации о размере, используем значения по умолчанию
        // или добавьте эти свойства в структуру Sample
        return 1000 // Значение по умолчанию
    }
    
    var imageHeight: Int {
        return 1000 // Значение по умолчанию
    }
}
