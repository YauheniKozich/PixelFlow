//
//  ConfigurationManager.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Менеджер конфигурации системы частиц
//

import Foundation
import CoreGraphics

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
        let totalPixels = image.width * image.height
        return totalPixels
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
}
