//
//  Protocols.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import CoreGraphics
import Foundation
import simd

// MARK: - Core Protocols

/// Протокол для анализа изображений
protocol ImageAnalyzer {
    func analyze(image: CGImage) throws -> ImageAnalysis
}

/// Протокол для сэмплинга пикселей
protocol PixelSampler {
    func samplePixels(from analysis: ImageAnalysis, targetCount: Int, config: ParticleGenerationConfig, image: CGImage) throws -> [Sample]
}

/// Протокол для сборки частиц
protocol ParticleAssembler {
    func assembleParticles(from samples: [Sample],
                           config: ParticleGenerationConfig,
                           screenSize: CGSize,
                           imageSize: CGSize,
                           originalImageSize: CGSize) -> [Particle]
}

/// Протокол для кэширования результатов
protocol CacheManager: AnyObject {
    func cache<T: Codable>(_ value: T, for key: String) throws
    func retrieve<T: Codable>(_ type: T.Type, for key: String) throws -> T?
    func clear()
}

/// Протокол для отслеживания прогресса генерации
protocol ParticleGeneratorDelegate: AnyObject {
    func generator(_ generator: ImageParticleGenerator, didUpdateProgress progress: Float, stage: String)
    func generator(_ generator: ImageParticleGenerator, didEncounterError error: Error)
    func generatorDidFinish(_ generator: ImageParticleGenerator, particles: [Particle])
}

/// Протокол для конфигурации генерации
protocol ParticleGeneratorConfiguration: Codable {
    var samplingStrategy: SamplingStrategy { get }
    var qualityPreset: QualityPreset { get }
    var enableCaching: Bool { get }
    var maxConcurrentOperations: Int { get }
}
