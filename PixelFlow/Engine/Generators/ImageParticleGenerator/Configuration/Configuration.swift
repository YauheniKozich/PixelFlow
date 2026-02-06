//
//  Configuration.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation

enum SamplingStrategy: Codable, Equatable {
    case uniform         // Равномерный сэмплинг
    case importance      // По важности пикселей
    case adaptive        // Адаптивная плотность
    case hybrid          // Комбинированный подход
    case advanced(SamplingAlgorithm)  // Продвинутые алгоритмы
}

enum QualityPreset: Codable {
    case draft     // Быстрый черновик
    case standard  // Стандартное качество
    case high      // Высокое качество
    case ultra     // Максимальное качество
}

// MARK: - Analysis-driven sampling tuning

struct AnalysisSamplingTuning: Codable {
    let edgeBiasStrength: Float
    let importanceThresholdMin: Float
    let importanceThresholdMax: Float
    let contrastWeightScale: Float
    let saturationWeightScale: Float
    let weightMin: Float
    let weightMax: Float
    let complexityMid: Int
    let complexityHigh: Int
    let edgeRadiusBoostMid: Int
    let edgeRadiusBoostHigh: Int
    let detailBoostScale: Float
    let detailBoostMax: Float
    let importantRatioMin: Float
    let importantRatioMax: Float

    static let `default` = AnalysisSamplingTuning(
        edgeBiasStrength: 0.6,
        importanceThresholdMin: 0.05,
        importanceThresholdMax: 0.9,
        contrastWeightScale: 0.5,
        saturationWeightScale: 0.5,
        weightMin: 0.1,
        weightMax: 2.0,
        complexityMid: 4,
        complexityHigh: 7,
        edgeRadiusBoostMid: 1,
        edgeRadiusBoostHigh: 2,
        detailBoostScale: 0.15,
        detailBoostMax: 0.2,
        importantRatioMin: 0.3,
        importantRatioMax: 0.9
    )
}

// MARK: - Performance (параметры нагрузки)

/// Параметры, влияющие на скорость и нагрузку.
struct PerformanceParams {
    let maxConcurrentOperations: Int
    let useSIMD: Bool
    let enableCaching: Bool
    let cacheSizeLimit: Int          // MB

    init(maxConcurrentOperations: Int,
         useSIMD: Bool,
         enableCaching: Bool,
         cacheSizeLimit: Int) {
        self.maxConcurrentOperations = maxConcurrentOperations
        self.useSIMD = useSIMD
        self.enableCaching = enableCaching
        self.cacheSizeLimit = cacheSizeLimit
    }
}

// MARK: - Основная конфигурация генерации частиц

/// Полный набор параметров, который передаётся в `ParticleSystem`.
struct ParticleGenerationConfig: Codable, ParticleGeneratorConfigurationWithDisplayMode {

    // Параметры сэмплинга
    var samplingStrategy: SamplingStrategy
    var qualityPreset: QualityPreset

    // Общие флаги
    var enableCaching: Bool
    let maxConcurrentOperations: Int

    // Параметры качества
    let importanceThreshold: Float
    let contrastWeight: Float
    let saturationWeight: Float
    let edgeDetectionRadius: Int
    let minParticleSize: Float
    let maxParticleSize: Float

    // Параметры производительности
    let useSIMD: Bool
    let cacheSizeLimit: Int          // MB

    // Параметры отображения
    var targetParticleCount: Int
    var imageDisplayMode: ImageDisplayMode
    var particleLifetime: Float
    var particleSpeed: Float
    var particleSizeUltra: ClosedRange<Float>?
    var particleSizeHigh: ClosedRange<Float>?
    var particleSizeStandard: ClosedRange<Float>?
    var particleSizeLow: ClosedRange<Float>?
    // Размер изображения в поинтах (если доступен) и масштаб экрана
    var imagePointWidth: Float?
    var imagePointHeight: Float?
    var screenScale: Float

    // Новые параметры сэмплинга
    let importantSamplingRatio: Float
    let topBottomRatio: Float
    var analysisSamplingTuning: AnalysisSamplingTuning?

    // MARK: – Инициализатор
    init(samplingStrategy: SamplingStrategy,
         qualityPreset: QualityPreset,
         enableCaching: Bool,
         maxConcurrentOperations: Int,
         importanceThreshold: Float,
         contrastWeight: Float,
         saturationWeight: Float,
         edgeDetectionRadius: Int,
         minParticleSize: Float,
         maxParticleSize: Float,
         useSIMD: Bool,
         cacheSizeLimit: Int,
         targetParticleCount: Int,
         imageDisplayMode: ImageDisplayMode = .fit,
         particleLifetime: Float = 1.0,
         particleSpeed: Float = 1.0,
         particleSizeUltra: ClosedRange<Float>? = nil,
         particleSizeHigh: ClosedRange<Float>? = nil,
         particleSizeStandard: ClosedRange<Float>? = nil,
         particleSizeLow: ClosedRange<Float>? = nil,
         imagePointWidth: Float? = nil,
         imagePointHeight: Float? = nil,
         screenScale: Float = 1.0,
         importantSamplingRatio: Float = 0.7,
         topBottomRatio: Float = 0.5,
         analysisSamplingTuning: AnalysisSamplingTuning? = .default) {

        self.samplingStrategy = samplingStrategy
        self.qualityPreset = qualityPreset
        self.enableCaching = enableCaching
        self.maxConcurrentOperations = maxConcurrentOperations
        self.importanceThreshold = importanceThreshold
        self.contrastWeight = contrastWeight
        self.saturationWeight = saturationWeight
        self.edgeDetectionRadius = edgeDetectionRadius
        self.minParticleSize = minParticleSize
        self.maxParticleSize = maxParticleSize
        self.useSIMD = useSIMD
        self.cacheSizeLimit = cacheSizeLimit
        self.targetParticleCount = targetParticleCount
        self.imageDisplayMode = imageDisplayMode
        self.particleLifetime = particleLifetime
        self.particleSpeed = particleSpeed
        self.particleSizeUltra = particleSizeUltra
        self.particleSizeHigh = particleSizeHigh
        self.particleSizeStandard = particleSizeStandard
        self.particleSizeLow = particleSizeLow
        self.imagePointWidth = imagePointWidth
        self.imagePointHeight = imagePointHeight
        self.screenScale = screenScale
        self.importantSamplingRatio = importantSamplingRatio
        self.topBottomRatio = topBottomRatio
        self.analysisSamplingTuning = analysisSamplingTuning
    }

    // MARK: – Пресеты

    /// Стандартный сбалансированный пресет.
    static var standard: ParticleGenerationConfig {
        ParticleGenerationConfig(
            samplingStrategy: .importance,
            qualityPreset: .standard,
            enableCaching: true,
            maxConcurrentOperations: ProcessInfo.processInfo.activeProcessorCount,
            importanceThreshold: 0.3,
            contrastWeight: 0.4,
            saturationWeight: 0.3,
            edgeDetectionRadius: 2,
            minParticleSize: 2.0,
            maxParticleSize: 8.0,
            useSIMD: true,
            cacheSizeLimit: 100,
            targetParticleCount: 1000,
            importantSamplingRatio: 0.7,
            topBottomRatio: 0.5
        )
    }

    /// Пресет «draft» – быстрый прототип, низкое качество.
    static let draft = ParticleGenerationConfig(
        samplingStrategy: .uniform,
        qualityPreset: .draft,
        enableCaching: false,
        maxConcurrentOperations: 2,
        importanceThreshold: 0.1,
        contrastWeight: 0.2,
        saturationWeight: 0.1,
        edgeDetectionRadius: 1,
        minParticleSize: 3.0,
        maxParticleSize: 6.0,
        useSIMD: false,
        cacheSizeLimit: 10,
        targetParticleCount: 500,
        importantSamplingRatio: 0.7,
        topBottomRatio: 0.5
    )

    /// Пресет «high» – более качественный, но уже не «ultra».
    static let high = ParticleGenerationConfig(
        samplingStrategy: .hybrid,
        qualityPreset: .high,
        enableCaching: true,
        maxConcurrentOperations: ProcessInfo.processInfo.activeProcessorCount,
        importanceThreshold: 0.45,
        contrastWeight: 0.45,
        saturationWeight: 0.35,
        edgeDetectionRadius: 3,
        minParticleSize: 1.5,
        maxParticleSize: 10.0,
        useSIMD: true,
        cacheSizeLimit: 300,
        targetParticleCount: 2000,
        importantSamplingRatio: 0.7,
        topBottomRatio: 0.5
    )

    /// Пресет «ultra» – максимум качества, максимум нагрузки.
    static let ultra = ParticleGenerationConfig(
        samplingStrategy: .hybrid,
        qualityPreset: .ultra,
        enableCaching: true,
        maxConcurrentOperations: ProcessInfo.processInfo.activeProcessorCount * 2,
        importanceThreshold: 0.5,
        contrastWeight: 0.5,
        saturationWeight: 0.4,
        edgeDetectionRadius: 3,
        minParticleSize: 1.0,
        maxParticleSize: 12.0,
        useSIMD: true,
        cacheSizeLimit: 500,
        targetParticleCount: 5000,
        importantSamplingRatio: 0.7,
        topBottomRatio: 0.5
    )

    // MARK: – «Legacy» имена 

    static let `default` = standard
    static let highQuality = ultra
}

// MARK: - Расширения, удобные свойства

extension ParticleGenerationConfig {

    /// Параметры сэмплинга, вычисляемые из текущего `qualityPreset`.
    var samplingParams: SamplingParams {
        switch qualityPreset {
        case .draft:
            return SamplingParams(
                importanceThreshold: importanceThreshold * 0.5,
                contrastWeight: contrastWeight * 0.7,
                saturationWeight: saturationWeight * 0.5,
                edgeRadius: max(1, edgeDetectionRadius - 1),
                importantSamplingRatio: self.importantSamplingRatio,
                topBottomRatio: self.topBottomRatio
            )
        case .standard:
            return SamplingParams(
                importanceThreshold: importanceThreshold,
                contrastWeight: contrastWeight,
                saturationWeight: saturationWeight,
                edgeRadius: edgeDetectionRadius,
                importantSamplingRatio: self.importantSamplingRatio,
                topBottomRatio: self.topBottomRatio
            )
        case .high:
            return SamplingParams(
                importanceThreshold: importanceThreshold * 1.2,
                contrastWeight: contrastWeight * 1.3,
                saturationWeight: saturationWeight * 1.2,
                edgeRadius: edgeDetectionRadius + 1,
                importantSamplingRatio: self.importantSamplingRatio,
                topBottomRatio: self.topBottomRatio
            )
        case .ultra:
            return SamplingParams(
                importanceThreshold: importanceThreshold * 1.5,
                contrastWeight: contrastWeight * 1.5,
                saturationWeight: saturationWeight * 1.4,
                edgeRadius: edgeDetectionRadius + 2,
                importantSamplingRatio: self.importantSamplingRatio,
                topBottomRatio: self.topBottomRatio
            )
        }
    }

    /// Параметры производительности, вынесенные в отдельный struct.
    var performanceParams: PerformanceParams {
        PerformanceParams(
            maxConcurrentOperations: maxConcurrentOperations,
            useSIMD: useSIMD,
            enableCaching: enableCaching,
            cacheSizeLimit: cacheSizeLimit
        )
    }
}
