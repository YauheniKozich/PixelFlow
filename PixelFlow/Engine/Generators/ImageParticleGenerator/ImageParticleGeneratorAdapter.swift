//
//  ImageParticleGeneratorAdapter.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Адаптер для совместимости новой архитектуры генератора с существующим API
//

import CoreGraphics
import MetalKit

/// Адаптер для совместимости нового ImageParticleGenerator с существующим API
final class ImageParticleGeneratorAdapter: ImageParticleGeneratorProtocol {

    // MARK: - Properties

    let image: CGImage
    var screenSize: CGSize = .zero

    private let coordinator: GenerationCoordinator
    private let logger: LoggerProtocol

    // MARK: - Initialization

    convenience init(image: CGImage, particleCount: Int) throws {
        try self.init(image: image, particleCount: particleCount, config: .default)
    }

    init(image: CGImage, particleCount: Int, config: ParticleGenerationConfig) throws {
        self.image = image
        self.logger = Logger.shared

        // Создаем новый координатор генерации
        self.coordinator = GenerationCoordinatorFactory.makeCoordinator()

        logger.info("ImageParticleGeneratorAdapter initialized with image \(image.width)x\(image.height)")
    }

    // MARK: - ImageParticleGeneratorProtocol

    func generateParticles() throws -> [Particle] {
        try generateParticles(screenSize: screenSize)
    }

    func generateParticles(screenSize: CGSize) throws -> [Particle] {
        logger.debug("Generating particles via adapter for screen size: \(screenSize)")

        // Настраиваем конфигурацию для совместимости
        var config = ParticleGenerationConfig.standard
        config.screenSize = screenSize

        // Выполняем генерацию через новый координатор с блокировкой
        var result: [Particle]?
        var generationError: Error?

        let semaphore = DispatchSemaphore(value: 0)

        Task {
            do {
                result = try await coordinator.generateParticles(
                    from: image,
                    config: config,
                    progress: { [self] progress, stage in
                        logger.debug("Generation progress: \(String(format: "%.1f%%", progress * 100)) - \(stage)")
                    }
                )
            } catch {
                generationError = error
            }
            semaphore.signal()
        }

        semaphore.wait()

        if let error = generationError {
            throw error
        }

        guard let particles = result else {
            throw GeneratorError.analysisFailed(reason: "Generation failed without error")
        }

        logger.info("Generated \(particles.count) particles via adapter")
        return particles
    }

    func updateScreenSize(_ size: CGSize) {
        screenSize = size
        logger.debug("Updated screen size to: \(size)")
    }

    func clearCache() {
        // Очищаем кэш через координатор
        coordinator.cancelGeneration()
        logger.debug("Cache cleared via adapter")
    }

    // MARK: - Additional Methods for Compatibility

    /// Синхронная версия генерации (для совместимости)
    func generateParticlesSync() async throws -> [Particle] {
        // Для совместимости с существующим кодом
        // В новой архитектуре все async, поэтому оборачиваем
        return try await generateParticles()
    }

    /// Генерация с прогрессом (расширенная совместимость)
    func generateParticlesWithProgress(
        _ progressCallback: @escaping (Float, String) -> Void
    ) async throws -> [Particle] {

        var config = ParticleGenerationConfig.standard
        config.screenSize = screenSize

        return try await coordinator.generateParticles(
            from: image,
            config: config,
            progress: progressCallback
        )
    }

    /// Проверяет доступность генерации
    var isReady: Bool {
        !coordinator.isGenerating
    }

    /// Текущий статус генерации
    var generationStatus: String {
        if coordinator.isGenerating {
            return "Generating (\(Int(coordinator.currentProgress * 100))%) - \(coordinator.currentStage)"
        } else {
            return "Ready"
        }
    }
}

// MARK: - Factory for Easy Migration

extension ImageParticleGenerator {
    /// Создает адаптер для постепенной миграции
    static func createAdapter(image: CGImage, particleCount: Int, config: ParticleGenerationConfig = .standard) throws -> ImageParticleGeneratorAdapter {
        try ImageParticleGeneratorAdapter(image: image, particleCount: particleCount, config: config)
    }

    /// Создает новый генератор с возможностью fallback на адаптер
    static func createWithFallback(image: CGImage, particleCount: Int, config: ParticleGenerationConfig = .standard) throws -> ImageParticleGeneratorProtocol {
        do {
            // Пытаемся создать новый генератор
            return try ImageParticleGenerator(image: image, particleCount: particleCount, config: config)
        } catch {
            Logger.shared.warning("Failed to create new generator, falling back to adapter: \(error)")
            // Fallback на адаптер для совместимости
            return try ImageParticleGeneratorAdapter(image: image, particleCount: particleCount, config: config)
        }
    }
}

// MARK: - Migration Helper

struct GeneratorMigrationHelper {
    /// Миграционный статус
    enum MigrationStatus {
        case legacy      // Только старый генератор
        case hybrid      // Старый + адаптер
        case migrated    // Только новый генератор
    }

    static var currentStatus: MigrationStatus {
        // Определяем статус на основе фич флагов или конфигурации
        // Пока что всегда hybrid для совместимости
        .hybrid
    }

    static func createGenerator(
        image: CGImage,
        particleCount: Int,
        config: ParticleGenerationConfig = .standard
    ) throws -> ImageParticleGeneratorProtocol {

        switch currentStatus {
        case .legacy:
            return try ImageParticleGenerator(image: image, particleCount: particleCount, config: config)

        case .hybrid, .migrated:
            // Используем новый адаптер для совместимости
            return try ImageParticleGeneratorAdapter(image: image, particleCount: particleCount, config: config)
        }
    }

    static func performanceComparison(
        image: CGImage,
        particleCount: Int,
        config: ParticleGenerationConfig = .standard
    ) async -> PerformanceComparison {

        var legacyTime: TimeInterval = 0
        var newTime: TimeInterval = 0
        var legacyParticles: Int = 0
        var newParticles: Int = 0

        // Замер производительности старого генератора
        do {
            let start = CACurrentMediaTime()
            let legacyGenerator = try ImageParticleGenerator(image: image, particleCount: particleCount, config: config)
            let particles = try legacyGenerator.generateParticles()
            legacyTime = CACurrentMediaTime() - start
            legacyParticles = particles.count
        } catch {
            Logger.shared.error("Legacy generator failed: \(error)")
        }

        // Замер производительности нового генератора
        do {
            let start = CACurrentMediaTime()
            let newGenerator = try ImageParticleGeneratorAdapter(image: image, particleCount: particleCount, config: config)
            let particles = try await newGenerator.generateParticles()
            newTime = CACurrentMediaTime() - start
            newParticles = particles.count
        } catch {
            Logger.shared.error("New generator failed: \(error)")
        }

        return PerformanceComparison(
            legacyTime: legacyTime,
            newTime: newTime,
            legacyParticles: legacyParticles,
            newParticles: newParticles,
            speedup: legacyTime > 0 ? newTime / legacyTime : 0
        )
    }
}

/// Результат сравнения производительности
struct PerformanceComparison {
    let legacyTime: TimeInterval
    let newTime: TimeInterval
    let legacyParticles: Int
    let newParticles: Int
    let speedup: Double

    var description: String {
        """
        Performance Comparison:
        Legacy: \(String(format: "%.3fs", legacyTime)) (\(legacyParticles) particles)
        New:    \(String(format: "%.3fs", newTime)) (\(newParticles) particles)
        Speedup: \(String(format: "%.2fx", speedup)) (\(speedup > 1 ? "faster" : "slower"))
        """
    }
}