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

// MARK: - Public API Errors
public enum ParticleAssemblerError: Error, LocalizedError {
    case emptySamples
    case invalidImageSize(CGSize)
    case invalidScreenSize(CGSize)
    case invalidOriginalImageSize(CGSize)

    public var errorDescription: String? {
        switch self {
        case .emptySamples:
            return "Samples array is empty."
        case .invalidImageSize(let size):
            return "Invalid image size: \(size)."
        case .invalidScreenSize(let size):
            return "Invalid screen size: \(size)."
        case .invalidOriginalImageSize(let size):
            return "Invalid original image size: \(size)."
        }
    }
}

final class DefaultParticleAssembler: ParticleAssembler, ParticleAssemblerProtocol {
    
    // MARK: - Constants for Particle Assembly
    
    private let config: ParticleGenerationConfig
    
    // ============================================================================
    // VELOCITY & MOTION CONSTANTS
    // ============================================================================
    // КРИТИЧНО: Скорость должна быть в NDC пространстве [-1, 1], а не в пиксельях!
    // NDC диапазон: 2.0 (от -1 до 1), тогда как пиксельное пространство может быть 1000+
    // Поэтому используем намного меньшие значения для NDC
    private let maxSpeedNDC: Float = 0.5              // максимальная скорость в NDC координатах на кадр
    private let velocityBaseAmount: Float = 0.1       // базовая амплитуда скорости в NDC
    private let chaosFactor: Float = 0.5              // минимальный коэффициент хаоса
    private let chaosRandomRange: UInt32 = 200        // диапазон случайности для хаоса
    private let velocityRandomRange: UInt32 = 500     // диапазон случайности для скорости
    
    // ============================================================================
    // QUALITY MULTIPLIERS (зависят от preset, но не параметризованы)
    // ============================================================================
    // Эти значения контролируют размер частиц в зависимости от качества
    private let qualityMultiplierUltra: Float = 1.0   // Ultra: наименьший размер (максимум частиц)
    private let qualityMultiplierHigh: Float = 1.2    // High: средний размер
    private let qualityMultiplierStandard: Float = 1.5  // Standard: больший размер
    private let qualityMultiplierDraft: Float = 2.0   // Draft: максимальный размер (минимум частиц)
    
    // ============================================================================
    // SIZE RANGES (по качеству)
    // ============================================================================
    private let sizeRangeUltra: ClosedRange<Float> = 0.8...15.0
    private let sizeRangeHigh: ClosedRange<Float> = 1.5...12.0
    private let sizeRangeStandard: ClosedRange<Float> = 2.0...9.0
    private let sizeRangeDraft: ClosedRange<Float> = 3.0...7.0
    
    init(config: ParticleGenerationConfig) {
        self.config = config
    }
    
    // MARK: - Public API (conforms to `ParticleAssembler` protocol)
    // The protocol expects a non‑throwing method, therefore we catch any internal errors
    // and return an empty array while logging the failure. This keeps the public contract
    // stable and avoids breaking existing callers.
    func assembleParticles(
        from samples: [Sample],
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        imageSize: CGSize,
        originalImageSize: CGSize
    ) -> [Particle] {
        do {
            return try assembleParticlesOriginal(
                from: samples,
                config: config,
                screenSize: screenSize,
                imageSize: imageSize,
                originalImageSize: originalImageSize
            )
        } catch {
            // Log the error for debugging; in production we simply return an empty list.
            Logger.shared.error("Particle assembly failed: \(error)")
            return []
        }
    }
    
    // MARK: - Оригинальная функция
    
    private func assembleParticlesOriginal(
        from samples: [Sample],
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        imageSize: CGSize,
        originalImageSize: CGSize
    ) throws -> [Particle] {
        
        // MARK: - Validation (throws)
        guard !samples.isEmpty else {
            throw ParticleAssemblerError.emptySamples
        }
        guard imageSize.width > 0, imageSize.height > 0 else {
            throw ParticleAssemblerError.invalidImageSize(imageSize)
        }
        guard screenSize.width > 0, screenSize.height > 0 else {
            throw ParticleAssemblerError.invalidScreenSize(screenSize)
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
                    originalImageSize: originalImageSize,
                    screenSize: screenSize
                )
            )
        }
        
        #if DEBUG
        Logger.shared.debug("Сборка частиц завершена: \(particles.count) частиц")
        if particles.count >= 10 {
            Logger.shared.debug("Первые 10 частиц (КОНТРОЛЬ ЦВЕТОВ):")
            for i in 0..<10 {
                let p = particles[i]
                let r = String(format: "%.3f", p.color.x)
                let g = String(format: "%.3f", p.color.y)
                let b = String(format: "%.3f", p.color.z)
                let a = String(format: "%.3f", p.color.w)
                let origR = String(format: "%.3f", p.originalColor.x)
                let origG = String(format: "%.3f", p.originalColor.y)
                let origB = String(format: "%.3f", p.originalColor.z)
                let origA = String(format: "%.3f", p.originalColor.w)
                Logger.shared.debug("  [\(i)] 🎨 color=(\(r),\(g),\(b),\(a)) originalColor=(\(origR),\(origG),\(origB),\(origA))")
                Logger.shared.debug("       pos=(\(String(format: "%.2f", p.position.x)), \(String(format: "%.2f", p.position.y))) vel=(\(String(format: "%.3f", p.velocity.x)), \(String(format: "%.3f", p.velocity.y)))")
            }
        }
        #endif
        
        return particles
    }
    
    // MARK: - Private Methods
    
    /// Получаем режим отображения из конфигурации
    @inline(__always)
    private func getDisplayMode(from config: ParticleGenerationConfig) -> ImageDisplayMode {
        if let configWithDisplayMode = config as? ParticleGeneratorConfigurationWithDisplayMode {
            return configWithDisplayMode.imageDisplayMode
        }
        return .fit
    }
    
    /// Расчет параметров трансформации координат
    // Helper to compute scaled size and offset for .fit/.fill modes
    @inline(__always)
    private func scaledSizeAndOffset(screenSize: CGSize, imageSize: CGSize, scale: CGFloat) -> (size: CGSize, offset: CGPoint) {
        let scaled = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(
            x: max(0, (screenSize.width - scaled.width) / 2),
            y: max(0, (screenSize.height - scaled.height) / 2)
        )
        return (scaled, offset)
    }

    @inline(__always)
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
            let (_, offset) = scaledSizeAndOffset(screenSize: screenSize, imageSize: imageSize, scale: scale)
            return TransformationParams(scaleX: scale, scaleY: scale, offset: offset, mode: .fit)
        case .fill:
            let scale: CGFloat = (aspectImage > aspectScreen)
                ? screenSize.height / imageSize.height
                : screenSize.width  / imageSize.width
            let (_, offset) = scaledSizeAndOffset(screenSize: screenSize, imageSize: imageSize, scale: scale)
            return TransformationParams(scaleX: scale, scaleY: scale, offset: offset, mode: .fill)
        case .stretch:
            let scaleX = screenSize.width  / imageSize.width
            let scaleY = screenSize.height / imageSize.height
            return TransformationParams(scaleX: scaleX, scaleY: scaleY, offset: .zero, mode: .stretch)
        case .center:
            let offset = CGPoint(
                x: (screenSize.width  - imageSize.width)  / 2,
                y: (screenSize.height - imageSize.height) / 2
            )
            return TransformationParams(scaleX: 1.0, scaleY: 1.0, offset: offset, mode: .center)
        }
    }
    
    /// Создание отдельной частицы
    @inline(__always)
    private func createParticle(
        from sample: Sample,
        index: Int,
        transformation: TransformationParams,
        sizeRange: ClosedRange<Float>,
        sizeVariation: Float,
        config: ParticleGenerationConfig,
        originalImageSize: CGSize,
        screenSize: CGSize
    ) -> Particle {
        
        var particle = Particle()
        
        // Защита от некорректных размеров
        guard originalImageSize.width > 0, originalImageSize.height > 0 else {
            // В случае ошибки возвращаем «пустую» частицу, но в продакшн‑сборке лучше бросать ошибку.
            return particle
        }
        
        // Используем нормализованные координаты изображения [0…1]
        let nx = CGFloat(sample.x) / originalImageSize.width
        let ny = CGFloat(sample.y) / originalImageSize.height

        // Применяем масштаб и смещение, полученные из `TransformationParams`
        // `offset` учитывает центрирование изображения в режимах .fit/.fill.
        // Позиция уже нормализована относительно оригинального изображения,
        // поэтому масштабировать её дополнительно не требуется – достаточно добавить
        // смещение, чтобы частицы правильно позиционировались на экране.
        let screenX = nx * screenSize.width + transformation.offset.x
        let screenY = ny * screenSize.height + transformation.offset.y

        // normalized → NDC [-1…1]
        // Инверсия Y: UIKit (Y вниз) → Metal (Y вверх)
        let ndcX = Float(screenX / screenSize.width * 2.0 - 1.0)
        let ndcY = Float((1.0 - screenY / screenSize.height) * 2.0 - 1.0)

        // Позиция частицы сразу в NDC
        particle.position = SIMD3<Float>(ndcX, ndcY, 0)
        particle.targetPosition = particle.position
        
        particle.color = sample.color
        particle.originalColor = sample.color
        
        // Размер частицы привязан к реальному размеру пикселя изображения на экране
        let pixelWidth  = Float(transformation.scaleX)
        let pixelHeight = Float(transformation.scaleY)
        let pixelSize   = min(pixelWidth, pixelHeight)

        // Применяем возможное увеличение для качества (Ultra / High / Draft)
        let qualityMultiplier: Float
        switch config.qualityPreset {
        case .ultra:    qualityMultiplier = qualityMultiplierUltra
        case .high:     qualityMultiplier = qualityMultiplierHigh
        case .standard: qualityMultiplier = qualityMultiplierStandard
        case .draft:    qualityMultiplier = qualityMultiplierDraft
        @unknown default:
            qualityMultiplier = qualityMultiplierUltra // fallback
        }

        particle.size = pixelSize * qualityMultiplier
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
        
        // Ограничение скорости частиц в NDC пространстве
        let randomChaosFactor = chaosFactor + Float(xorshift32(&seed) % chaosRandomRange) / 1000.0
        let vx = -velocityBaseAmount + Float(xorshift32(&seed) % velocityRandomRange) / 1000.0
        let vy = -velocityBaseAmount + Float(xorshift32(&seed) % velocityRandomRange) / 1000.0

        particle.idleChaoticMotion = 0
        particle.velocity = SIMD3<Float>(vx, vy, 0) * maxSpeedNDC * randomChaosFactor
        
        return particle
    }
    
    private func getSizeRange(for preset: QualityPreset) -> ClosedRange<Float> {
        if let configWithDisplayMode = config as? ParticleGeneratorConfigurationWithDisplayMode {
            switch preset {
            case .ultra:
                return configWithDisplayMode.particleSizeUltra ?? sizeRangeUltra
            case .high:
                return configWithDisplayMode.particleSizeHigh ?? sizeRangeHigh
            case .standard:
                return configWithDisplayMode.particleSizeStandard ?? sizeRangeStandard
            case .draft:
                return configWithDisplayMode.particleSizeLow ?? sizeRangeDraft
            }
        }
        
        // Значения по умолчанию (используем константы класса)
        let defaultRanges: [QualityPreset: ClosedRange<Float>] = [
            .ultra: sizeRangeUltra,
            .high: sizeRangeHigh,
            .standard: sizeRangeStandard,
            .draft: sizeRangeDraft
        ]
        return defaultRanges[preset] ?? sizeRangeStandard
    }
    
    /// Получение скорости частицы
    private func getParticleSpeed(from config: ParticleGenerationConfig) -> Float {
        if let configWithDisplayMode = config as? ParticleGeneratorConfigurationWithDisplayMode {
            return configWithDisplayMode.particleSpeed
        }
        return 1.0
    }
}
