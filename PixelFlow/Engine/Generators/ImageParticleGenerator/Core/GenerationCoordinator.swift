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

    private let stateQueue = DispatchQueue(label: "com.generation.coordinator.state")
    private var _isGenerating = false
    private var _currentProgress: Float = 0.0
    private var _currentStage = "Idle"

    private var currentTask: Task<[Particle], Error>?
    private var activeGenerationID: UUID?
    private var cancellationRequested = false

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

        let generationID = UUID()
        while true {
            try Task.checkCancellation()
            let canStart = stateQueue.sync { () -> Bool in
                guard !self._isGenerating else { return false }
                self._isGenerating = true
                self._currentProgress = 0.0
                self._currentStage = "Starting"
                self.activeGenerationID = generationID
                self.cancellationRequested = false
                return true
            }
            if canStart { break }
            // The previous run owns the pipeline until its computation exits.
            if let previousTask = stateQueue.sync(execute: { currentTask }) {
                _ = try? await previousTask.value
            }
            await Task.yield()
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
                var cacheKey: String?
                if config.enableCaching {
                    do {
                        cacheKey = try self.cacheKey(for: image, config: config, screenSize: screenSize)
                    } catch {
                        self.logger.warning("Cannot create generation cache key: \(error)")
                    }
                }
                try Task.checkCancellation()
                var cachedParticles: [Particle]?
                if let cacheKey {
                    do {
                        cachedParticles = try self.cacheManager.retrieve([Particle].self, for: cacheKey)
                    } catch {
                        self.logger.warning("Cannot read generation cache: \(error)")
                    }
                }
                if let cachedParticles {

                    // Проверяем, что количество частиц в кэше соответствует целевому
                    if cachedParticles.count == config.targetParticleCount {
                        await MainActor.run {
                            if self.isGenerationActive(id: generationID) {
                                progress(1.0, "Loaded from cache")
                            }
                        }

                        self.logger.info("Loaded \(cachedParticles.count) particles from cache")
                        try Task.checkCancellation()
                        return cachedParticles
                    }
                }

                // Выполнение генерации через pipeline
                let particles = try await self.pipeline.execute(
                    image: image,
                    config: config,
                    screenSize: screenSize
                ) { progressValue, stage in
                    self.stateQueue.async {
                        guard self.activeGenerationID == generationID, !self.cancellationRequested else { return }
                        self._currentProgress = progressValue
                        self._currentStage = stage
                    }

                    DispatchQueue.main.async {
                        guard self.isGenerationActive(id: generationID) else { return }
                        progress(progressValue, stage)
                    }
                }

                // Кэширование результата
                try Task.checkCancellation()
                if let cacheKey {
                    do {
                        try self.cacheManager.cache(particles, for: cacheKey)
                    } catch {
                        self.logger.warning("Cannot store generation cache: \(error)")
                    }
                }
                try Task.checkCancellation()

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
        let shouldCancelImmediately = stateQueue.sync { () -> Bool in
            guard activeGenerationID == generationID else { return true }
            currentTask = generationTask
            return cancellationRequested
        }
        if shouldCancelImmediately { generationTask.cancel() }

        // Ожидание завершения
        do {
            let particles = try await withTaskCancellationHandler {
                try await generationTask.value
            } onCancel: {
                generationTask.cancel()
            }
            try Task.checkCancellation()
            guard isGenerationActive(id: generationID) else { throw GeneratorError.cancelled }

            finishGeneration(id: generationID, progress: 1.0, stage: "Completed")

            return particles

        } catch {
            let stage: String
            if Task.isCancelled || error is CancellationError {
                stage = "Cancelled"
            } else if let generatorError = error as? GeneratorError, case .cancelled = generatorError {
                stage = "Cancelled"
            } else {
                stage = "Failed"
            }

            finishGeneration(id: generationID, progress: 0.0, stage: stage)
            throw error
        }
    }

    func cancelGeneration() {
        logger.info("Cancelling particle generation")

        let taskToCancel = stateQueue.sync { () -> Task<[Particle], Error>? in
            let task = currentTask
            cancellationRequested = _isGenerating
            _currentProgress = 0.0
            _currentStage = "Cancelled"
            return task
        }
        taskToCancel?.cancel()

        // Task передаёт отмену вложенным операциям; общий менеджер не отменяем,
        // чтобы завершение старого запуска не затронуло следующий.
    }

    // MARK: - Private Methods

    private func finishGeneration(id: UUID, progress: Float, stage: String) {
        stateQueue.sync {
            guard activeGenerationID == id else { return }
            self._isGenerating = false
            self._currentProgress = progress
            self._currentStage = stage
            self.currentTask = nil
            self.activeGenerationID = nil
            self.cancellationRequested = false
        }
    }

    private func isGenerationActive(id: UUID) -> Bool {
        stateQueue.sync { activeGenerationID == id && !cancellationRequested }
    }

    private func cacheKey(for image: CGImage, config: ParticleGenerationConfig, screenSize: CGSize) throws -> String {
        let configFingerprint = try hashConfig(config)
        let imageFingerprint = try PixelCache.create(from: image).contentFingerprint
        let components = [
            "v4-image-content",
            "\(image.width)x\(image.height)",
            imageFingerprint,
            "\(screenSize.width)x\(screenSize.height)",
            configFingerprint
        ]
        return "generation_" + components.joined(separator: "_")
    }

    private func hashConfig(_ config: ParticleGenerationConfig) throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        let data = try encoder.encode(config)
        let hash = SHA256.hash(data: data)
        return hash.compactMap { String(format: "%02x", $0) }.joined()
    }

    func clearCache() {
        logger.info("Clearing generation cache")
        cacheManager.clear()
    }
}
