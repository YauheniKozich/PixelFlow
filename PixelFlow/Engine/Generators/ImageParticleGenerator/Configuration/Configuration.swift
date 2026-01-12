//
//  Configuration.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation

// MARK: - Configuration

/// Конфигурация генерации частиц
struct ParticleGenerationConfig: Codable, ParticleGeneratorConfiguration {
    let samplingStrategy: SamplingStrategy
    let qualityPreset: QualityPreset
    let enableCaching: Bool
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
    let cacheSizeLimit: Int // MB

    /// Конфигурация по умолчанию
    static let `default` = ParticleGenerationConfig(
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
        cacheSizeLimit: 100
    )

    /// Быстрая конфигурация для прототипов
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
        cacheSizeLimit: 10
    )

    /// Высококачественная конфигурация
    static let highQuality = ParticleGenerationConfig(
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
        cacheSizeLimit: 500
    )
}

// MARK: - Configuration Extensions

extension ParticleGenerationConfig {
    /// Возвращает параметры сэмплинга в зависимости от качества
    var samplingParams: SamplingParams {
        switch qualityPreset {
        case .draft:
            return SamplingParams(
                importanceThreshold: importanceThreshold * 0.5,
                contrastWeight: contrastWeight * 0.7,
                saturationWeight: saturationWeight * 0.5,
                edgeRadius: max(1, edgeDetectionRadius - 1)
            )
        case .standard:
            return SamplingParams(
                importanceThreshold: importanceThreshold,
                contrastWeight: contrastWeight,
                saturationWeight: saturationWeight,
                edgeRadius: edgeDetectionRadius
            )
        case .high:
            return SamplingParams(
                importanceThreshold: importanceThreshold * 1.2,
                contrastWeight: contrastWeight * 1.3,
                saturationWeight: saturationWeight * 1.2,
                edgeRadius: edgeDetectionRadius + 1
            )
        case .ultra:
            return SamplingParams(
                importanceThreshold: importanceThreshold * 1.5,
                contrastWeight: contrastWeight * 1.5,
                saturationWeight: saturationWeight * 1.4,
                edgeRadius: edgeDetectionRadius + 2
            )
        }
    }

    /// Возвращает параметры производительности
    var performanceParams: PerformanceParams {
        PerformanceParams(
            maxConcurrentOperations: maxConcurrentOperations,
            useSIMD: useSIMD,
            enableCaching: enableCaching,
            cacheSizeLimit: cacheSizeLimit
        )
    }
}

/// Параметры сэмплинга
struct SamplingParams {
    let importanceThreshold: Float
    let contrastWeight: Float
    let saturationWeight: Float
    let edgeRadius: Int
}

/// Параметры производительности
struct PerformanceParams {
    let maxConcurrentOperations: Int
    let useSIMD: Bool
    let enableCaching: Bool
    let cacheSizeLimit: Int
}
