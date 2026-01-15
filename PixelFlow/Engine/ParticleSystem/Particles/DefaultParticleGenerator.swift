//
//  DefaultParticleGenerator.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Заглушка для генератора частиц
//

import CoreGraphics

/// Заглушка для генератора частиц
final class DefaultParticleGenerator: ParticleGeneratorProtocol {

    // MARK: - Properties

    var image: CGImage? { nil }
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(logger: LoggerProtocol = Logger.shared) {
        self.logger = logger
        logger.info("DefaultParticleGenerator initialized (stub)")
    }

    // MARK: - ParticleGeneratorProtocol

    func generateParticles(from image: CGImage, config: ParticleGenerationConfig, screenSize: CGSize) throws -> [Particle] {
        logger.warning("DefaultParticleGenerator.generateParticles called - stub implementation")

        // Создаем заглушки частиц для тестирования
        let particleCount = 1000 // Фиксированное количество для заглушки
        var particles = [Particle]()

        for i in 0..<particleCount {
            var particle = Particle()

            // Простое распределение
            let angle = Float(i) / Float(particleCount) * 2 * .pi
            particle.position = SIMD3<Float>(
                cos(angle) * 100,
                sin(angle) * 100,
                0
            )

            particle.color = SIMD4<Float>(1, 1, 1, 1)
            particle.size = 5.0

            particles.append(particle)
        }

        logger.info("Generated \(particles.count) stub particles")
        return particles
    }

    func clearCache() {
        logger.debug("DefaultParticleGenerator.clearCache called")
    }
}
