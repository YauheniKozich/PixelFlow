//
//  GenerationCoordinator.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Главный координатор генерации частиц из изображений
//

import CoreGraphics
import Foundation

/// Главный координатор генерации частиц из изображений
final class GenerationCoordinator: NSObject, GenerationCoordinatorProtocol {

    // MARK: - Dependencies

    private let pipeline: GenerationPipelineProtocol
    private let operationManager: OperationManagerProtocol
    private let memoryManager: MemoryManagerProtocol
    private let cacheManager: CacheManagerProtocol
    private let logger: LoggerProtocol

    // MARK: - State

    private let stateQueue = DispatchQueue(label: "com.generation.coordinator.state", attributes: .concurrent)
    private var _isGenerating = false
    private var _currentProgress: Float = 0.0
    private var _currentStage = "Idle"

    private var currentTask: Task<[Particle], Error>?

    // MARK: - Initialization

    init(pipeline: GenerationPipelineProtocol,
         operationManager: OperationManagerProtocol,
         memoryManager: MemoryManagerProtocol,
         cacheManager: CacheManagerProtocol,
         logger: LoggerProtocol = Logger.shared) {

        self.pipeline = pipeline
        self.operationManager = operationManager
        self.memoryManager = memoryManager
        self.cacheManager = cacheManager
        self.logger = logger

        super.init()

        logger.info("GenerationCoordinator initialized")
    }

    // MARK: - GenerationCoordinatorProtocol

    var isGenerating: Bool {
        stateQueue.sync { _isGenerating }
    }

    var currentProgress: Float {
        stateQueue.sync { _currentProgress }
    }

    var currentStage: String {
        stateQueue.sync { _currentStage }
    }

    func generateParticles(
        from image: CGImage,
        config: ParticleGenerationConfig,
        progress: @escaping (Float, String) -> Void
    ) async throws -> [Particle] {

        // Проверка состояния
        guard !isGenerating else {
            throw GeneratorError.cancelled
        }

        // Обновление состояния
        stateQueue.async(flags: .barrier) {
            self._isGenerating = true
            self._currentProgress = 0.0
            self._currentStage = "Starting"
        }

        logger.info("Starting particle generation for image \(image.width)x\(image.height)")

        // Создание задачи генерации
        let generationTask = Task { [weak self] () -> [Particle] in
            guard let self = self else {
                throw GeneratorError.cancelled
            }

            do {
                // Проверка кэша
                let cacheKey = self.cacheKey(for: image, config: config)
                if config.enableCaching,
                   let cachedParticles: [Particle] = try await self.cacheManager.retrieve([Particle].self, for: cacheKey) {

                    await MainActor.run {
                        progress(1.0, "Loaded from cache")
                    }

                    self.logger.info("Loaded \(cachedParticles.count) particles from cache")
                    return cachedParticles
                }

                // Выполнение генерации через pipeline
                let particles = try await self.pipeline.execute(
                    image: image,
                    config: config
                ) { progressValue, stage in
                    self.stateQueue.async(flags: .barrier) {
                        self._currentProgress = progressValue
                        self._currentStage = stage
                    }

                    Task { @MainActor in
                        progress(progressValue, stage)
                    }
                }

                // Кэширование результата
                if config.enableCaching {
                    try await self.cacheManager.cache(particles, for: cacheKey)
                    self.logger.debug("Cached \(particles.count) particles")
                }

                // Отслеживание памяти
                self.memoryManager.trackMemoryUsage(Int64(particles.count * MemoryLayout<Particle>.size))

                self.logger.info("Generated \(particles.count) particles successfully")
                return particles

            } catch {
                self.logger.error("Generation failed: \(error)")
                throw error
            }
        }

        // Сохранение ссылки на задачу для отмены
        self.currentTask = generationTask

        // Ожидание завершения
        do {
            let particles = try await generationTask.value

            // Очистка состояния
            stateQueue.async(flags: .barrier) {
                self._isGenerating = false
                self._currentProgress = 1.0
                self._currentStage = "Completed"
            }

            return particles

        } catch {
            // Очистка состояния при ошибке
            stateQueue.async(flags: .barrier) {
                self._isGenerating = false
                self._currentProgress = 0.0
                self._currentStage = "Failed"
            }
            throw error
        }
    }

    func cancelGeneration() {
        logger.info("Cancelling particle generation")

        // Отмена текущей задачи
        currentTask?.cancel()
        currentTask = nil

        // Обновление состояния
        stateQueue.async(flags: .barrier) {
            self._isGenerating = false
            self._currentProgress = 0.0
            self._currentStage = "Cancelled"
        }

        // Отмена в pipeline и operation manager
        operationManager.cancelAllOperations()
    }

    // MARK: - Private Methods

    private func cacheKey(for image: CGImage, config: ParticleGenerationConfig) -> String {
        let components = [
            "\(image.width)x\(image.height)",
            "\(config.qualityPreset)",
            "\(config.samplingStrategy)",
            String(format: "%.2f", config.importanceThreshold)
        ]
        return "generation_" + components.joined(separator: "_")
    }
}

// MARK: - Factory

enum GenerationCoordinatorFactory {
    static func makeCoordinator() -> GenerationCoordinator {
        // Получить зависимости из DI контейнера
        guard let pipeline = resolve(GenerationPipelineProtocol.self),
              let operationManager = resolve(OperationManagerProtocol.self),
              let memoryManager = resolve(MemoryManagerProtocol.self),
              let cacheManager = resolve(CacheManagerProtocol.self),
              let logger = resolve(LoggerProtocol.self) else {
            fatalError("Failed to resolve GenerationCoordinator dependencies")
        }

        return GenerationCoordinator(
            pipeline: pipeline,
            operationManager: operationManager,
            memoryManager: memoryManager,
            cacheManager: cacheManager,
            logger: logger
        )
    }
}