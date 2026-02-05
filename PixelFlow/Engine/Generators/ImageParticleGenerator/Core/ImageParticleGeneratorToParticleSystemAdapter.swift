//
//  ImageParticleGeneratorToParticleSystemAdapter.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Адаптер для интеграции GenerationCoordinator с ParticleSystemController
//

import CoreGraphics
import Foundation

/// Адаптер для интеграции GenerationCoordinator с ParticleSystemController
/// Реализует ParticleGeneratorProtocol, используя GenerationCoordinator внутри
final class ImageParticleGeneratorToParticleSystemAdapter: ParticleGeneratorProtocol {
    // MARK: - Properties

    var image: CGImage? { nil } // Не храним изображение, передаем в метод

    private let coordinator: GenerationCoordinator
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(coordinator: GenerationCoordinator, logger: LoggerProtocol) {
        self.coordinator = coordinator
        self.logger = logger
        logger.info("ImageParticleGeneratorToParticleSystemAdapter initialized")
    }

    // MARK: - ParticleGeneratorProtocol

    func generateParticles(from image: CGImage, config: ParticleGenerationConfig, screenSize: CGSize) async throws -> [Particle] {
        logger.info("Generating particles from image \(image.width)x\(image.height) with config: \(config.qualityPreset)")

        do {
            let particles = try await coordinator.generateParticles(
                from: image,
                config: config,
                screenSize: screenSize,
                progress: { progress, stage in
                    self.logger.debug("Generation progress: \(String(format: "%.1f%%", progress * 100)) - \(stage)")
                }
            )

            logger.info("Successfully generated \(particles.count) particles")
            return particles
        } catch {
            logger.error("Generation failed: \(error)")
            throw error
        }
    }



    func clearCache() {
        logger.debug("Clearing cache")
        coordinator.cancelGeneration()
        // Очистка кэша генератора
        coordinator.clearCache()
    }
}
