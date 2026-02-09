//
//  GenerationCoordinator.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Главный координатор генерации частиц из изображений
//

import CoreGraphics
import CryptoKit
import Foundation

// MARK: - Factory

enum GenerationCoordinatorFactory {
    static func makeCoordinator(in container: DIContainer) -> GenerationCoordinator {
        // Получить зависимости из DI контейнера
        guard let pipeline = container.resolve(GenerationPipelineProtocol.self),
              let operationManager = container.resolve(OperationManagerProtocol.self),
              let memoryManager = container.resolve(MemoryManagerProtocol.self),
              let cacheManager = container.resolve(CacheManagerProtocol.self),
              let logger = container.resolve(LoggerProtocol.self),
              let errorHandler = container.resolve(ErrorHandlerProtocol.self) else {
            fatalError("Failed to resolve GenerationCoordinator dependencies")
        }
        
        return GenerationCoordinator(
            pipeline: pipeline,
            operationManager: operationManager,
            memoryManager: memoryManager,
            cacheManager: cacheManager,
            logger: logger,
            errorHandler: errorHandler
        )
    }
}

final class GenerationCoordinator: NSObject, @unchecked Sendable, GenerationCoordinatorProtocol {

    // MARK: - Dependencies

    private let pipeline: GenerationPipelineProtocol
    private let operationManager: OperationManagerProtocol
    private let memoryManager: MemoryManagerProtocol
    private let cacheManager: CacheManagerProtocol
    private let logger: LoggerProtocol
    private let errorHandler: ErrorHandlerProtocol

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
         logger: LoggerProtocol = Logger.shared,
         errorHandler: ErrorHandlerProtocol) {

        self.pipeline = pipeline
        self.operationManager = operationManager
        self.memoryManager = memoryManager
        self.cacheManager = cacheManager
        self.logger = logger
        self.errorHandler = errorHandler

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
        screenSize: CGSize,
        progress: @escaping (Float, String) -> Void
    ) async throws -> [Particle] {

        let canStart = stateQueue.sync(flags: .barrier) { () -> Bool in
            guard !self._isGenerating else { return false }
            self._isGenerating = true
            self._currentProgress = 0.0
            self._currentStage = "Starting"
            return true
        }
        guard canStart else {
            throw GeneratorError.cancelled
        }

        logger.info("Starting particle generation for image \(image.width)x\(image.height)")

        // Создание задачи генерации
        let generationTask = Task { [weak self] () -> [Particle] in
            guard let self = self else {
                throw GeneratorError.cancelled
            }

            do {
                try Task.checkCancellation()
                // Проверка кэша
                let cacheKey = self.cacheKey(for: image, config: config, screenSize: screenSize)
                if config.enableCaching,
                   let cachedParticles: [Particle] = try self.cacheManager.retrieve([Particle].self, for: cacheKey) {

                    // Проверяем, что количество частиц в кэше соответствует целевому
                    if cachedParticles.count == config.targetParticleCount {
                        await MainActor.run {
                            progress(1.0, "Loaded from cache")
                        }

                        self.logger.info("Loaded \(cachedParticles.count) particles from cache")
                        return cachedParticles
                    } else {
                    }
                }

                // Выполнение генерации через pipeline
                let particles = try await self.pipeline.execute(
                    image: image,
                    config: config,
                    screenSize: screenSize
                ) { progressValue, stage in
                    self.stateQueue.async(flags: .barrier) {
                        self._currentProgress = progressValue
                        self._currentStage = stage
                    }

                    DispatchQueue.main.async {
                        progress(progressValue, stage)
                    }
                }

                // Кэширование результата
                if config.enableCaching {
                    try self.cacheManager.cache(particles, for: cacheKey)
                }

                // Отслеживание памяти
                self.memoryManager.trackMemoryUsage(Int64(particles.count * MemoryLayout<Particle>.size))

                self.logger.info("Generated \(particles.count) particles successfully")
                return particles

            } catch {
                if Task.isCancelled || error is CancellationError {
                    throw GeneratorError.cancelled
                }
                if let generatorError = error as? GeneratorError, case .cancelled = generatorError {
                    throw generatorError
                }
                self.errorHandler.handle(error, context: "Generation pipeline execution", recovery: .showToast("Не удалось сгенерировать частицы"))
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
                if Task.isCancelled || error is CancellationError {
                    self._currentStage = "Cancelled"
                } else if let generatorError = error as? GeneratorError, case .cancelled = generatorError {
                    self._currentStage = "Cancelled"
                } else {
                    self._currentStage = "Failed"
                }
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

    private func cacheKey(for image: CGImage, config: ParticleGenerationConfig, screenSize: CGSize) -> String {
        let configFingerprint = hashConfig(config)
        let components = [
            "v3-fullres-2026-02-07",
            "\(image.width)x\(image.height)",
            "\(Int(screenSize.width))x\(Int(screenSize.height))",
            configFingerprint
        ]
        return "generation_" + components.joined(separator: "_")
    }

    private func hashConfig(_ config: ParticleGenerationConfig) -> String {
        do {
            let data = try JSONEncoder().encode(config)
            let hash = SHA256.hash(data: data)
            return hash.compactMap { String(format: "%02x", $0) }.joined()
        } catch {
            logger.warning("Failed to hash config for cache key: \(error)")
            return "config_fallback"
        }
    }

    func clearCache() {
        logger.info("Clearing generation cache")
        cacheManager.clear()
    }
}
