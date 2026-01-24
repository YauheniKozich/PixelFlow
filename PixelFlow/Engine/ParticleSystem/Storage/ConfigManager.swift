//
//  ConfigurationManager.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Менеджер конфигурации системы частиц
//

import Foundation
import CoreGraphics

/// Менеджер конфигурации системы частиц
@MainActor
final class ConfigurationManager: ConfigurationManagerProtocol {

    private enum Constants {
        static let minParticles = 10_000
        static let maxParticles = 300_000
    }

    // MARK: - Properties

    var currentConfig: ParticleGenerationConfig = .standard
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(logger: LoggerProtocol) {
        self.logger = logger
        logger.info("ConfigurationManager initialized")
    }

    // MARK: - ConfigurationManagerProtocol

    func apply(_ config: ParticleGenerationConfig) {
        logger.info("Applying configuration: \(config.qualityPreset)")
        currentConfig = config
    }

    func optimalParticleCount(for image: CGImage, preset: QualityPreset) -> Int {
        let pixelCount = Float(image.width * image.height)

        // Плотности подобраны экспериментально
        let density: Float
        switch preset {
        case .draft:   density = 0.00004   // ≈ 4% от 4K-изображения
        case .standard: density = 0.00008
        case .high:    density = 0.00012
        case .ultra:   density = 0.00020
        }

        let raw = Int(pixelCount * density)
        let clamped = max(Constants.minParticles, min(raw, Constants.maxParticles))

        logger.debug("Calculated particle count - raw: \(raw), clamped: \(clamped) for preset: \(preset)")
        return clamped
    }

    func resetToDefaults() {
        logger.info("Resetting to default configuration")
        currentConfig = .standard
    }

    // MARK: - Public Methods

    func updateQualityPreset(_ preset: QualityPreset) {
        var newConfig = currentConfig
        newConfig.qualityPreset = preset
        apply(newConfig)
    }

    func updateSamplingStrategy(_ strategy: SamplingStrategy) {
        var newConfig = currentConfig
        newConfig.samplingStrategy = strategy
        apply(newConfig)
    }

    func getConfigurationInfo() -> String {
        """
        === Configuration ===
        Preset: \(currentConfig.qualityPreset)
        Sampling: \(currentConfig.samplingStrategy)
        Caching: \(currentConfig.enableCaching ? "ON" : "OFF")
        SIMD: \(currentConfig.useSIMD ? "ON" : "OFF")
        Concurrent ops: \(currentConfig.maxConcurrentOperations)
        Cache limit: \(currentConfig.cacheSizeLimit)MB
        Particle size: \(currentConfig.minParticleSize)-\(currentConfig.maxParticleSize)
        """
    }
}
