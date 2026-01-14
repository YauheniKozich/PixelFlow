//
//  ImageParticleGeneratorToParticleSystemAdapter.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Адаптер для интеграции GenerationCoordinator с ParticleSystemCoordinator
//

import CoreGraphics
import Foundation

/// Адаптер для интеграции GenerationCoordinator с ParticleSystemCoordinator
/// Реализует ParticleGeneratorProtocol, используя GenerationCoordinator внутри
final class ImageParticleGeneratorToParticleSystemAdapter: ParticleGeneratorProtocol {

    // MARK: - Properties

    var image: CGImage? { nil } // Не храним изображение, передаем в метод

    private let coordinator: GenerationCoordinator
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(coordinator: GenerationCoordinator, logger: LoggerProtocol = Logger.shared) {
        self.coordinator = coordinator
        self.logger = logger
        logger.info("ImageParticleGeneratorToParticleSystemAdapter initialized")
    }

    // MARK: - ParticleGeneratorProtocol

    func generateParticles(from image: CGImage, config: ParticleGenerationConfig) throws -> [Particle] {
        logger.info("Generating particles from image \(image.width)x\(image.height) with config: \(config.qualityPreset)")

        // Синхронная обертка для асинхронного координатора
        var result: [Particle]?
        var generationError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                result = try await coordinator.generateParticles(
                    from: image,
                    config: config,
                    progress: { progress, stage in
                        self.logger.debug("Generation progress: \(String(format: "%.1f%%", progress * 100)) - \(stage)")
                    }
                )
            } catch {
                generationError = error
                self.logger.error("Generation failed: \(error)")
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = generationError {
            throw error
        }

        guard let particles = result else {
            throw GeneratorError.analysisFailed(reason: "Generation failed without result")
        }

        logger.info("Successfully generated \(particles.count) particles")
        return particles
    }

    func updateScreenSize(_ size: CGSize) {
        logger.debug("Screen size updated to: \(size)")
        // GenerationCoordinator не имеет прямого метода updateScreenSize,
        // размер экрана передается в конфигурации
    }

    func clearCache() {
        logger.debug("Clearing cache")
        coordinator.cancelGeneration()
        // Дополнительная очистка кэша, если нужно
    }
}

// MARK: - Factory

extension ImageParticleGeneratorToParticleSystemAdapter {
    static func makeAdapter() -> ImageParticleGeneratorToParticleSystemAdapter {
        let coordinator = GenerationCoordinatorFactory.makeCoordinator()
        return ImageParticleGeneratorToParticleSystemAdapter(coordinator: coordinator)
    }
}
