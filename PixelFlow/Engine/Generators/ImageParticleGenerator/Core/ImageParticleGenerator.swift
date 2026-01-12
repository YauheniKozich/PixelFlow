//
//  ImageParticleGeneratorV2.swift
//  PixelFlow
//
//  НОВАЯ МОДУЛЬНАЯ РЕАЛИЗАЦИЯ ГЕНЕРАТОРА ЧАСТИЦ
//  - Компонентная архитектура
//  - Асинхронная генерация
//  - Улучшенная производительность
//  - Гибкая конфигурация
//

import CoreGraphics
import Foundation

/// Основной класс генератора частиц с модульной архитектурой
final class ImageParticleGenerator: ImageParticleGeneratorProtocol, ParticleGeneratorDelegate {

    // MARK: - Properties

    /// Исходное изображение
    let image: CGImage

    /// Целевое количество частиц
    let targetParticleCount: Int

    /// Размер экрана для позиционирования
    var screenSize: CGSize = .zero

    /// Конфигурация генерации
    let config: ParticleGenerationConfig

    /// Делегат для отслеживания прогресса
    weak var delegate: ParticleGeneratorDelegate?

    // MARK: - Components

    private let analyzer: ImageAnalyzer
    private let sampler: PixelSampler
    private let assembler: ParticleAssembler
    private let cacheManager: CacheManager

    // MARK: - State

    private var analysis: ImageAnalysis?
    private var generatedParticles: [Particle] = []

    private var isGenerating = false
    private var currentOperation: Operation?

    // MARK: - Synchronization

    private let stateQueue = DispatchQueue(label: "com.particlegen.state", attributes: .concurrent)
    private let generationQueue = OperationQueue()

    // MARK: - Initialization

    /// Создает генератор частиц с настройками по умолчанию
    convenience init(image: CGImage, particleCount: Int) throws {
        try self.init(image: image, particleCount: particleCount, config: .default)
    }

    /// Создает генератор частиц с пользовательской конфигурацией
    init(image: CGImage, particleCount: Int, config: ParticleGenerationConfig) throws {
        // Валидация входных данных
        guard image.width > 0, image.height > 0 else {
            throw GeneratorError.invalidImage
        }

        guard image.width <= 16384, image.height <= 16384 else {
            throw GeneratorError.invalidImage
        }

        guard particleCount > 0 else {
            throw GeneratorError.invalidParticleCount
        }

        guard particleCount <= 100000 else {
            throw GeneratorError.invalidParticleCount
        }

        // Валидация конфигурации
        guard config.maxConcurrentOperations > 0 else {
            throw GeneratorError.analysisFailed(reason: "Invalid maxConcurrentOperations")
        }

        guard config.importanceThreshold >= 0.0, config.importanceThreshold <= 1.0 else {
            throw GeneratorError.analysisFailed(reason: "Invalid importanceThreshold")
        }

        self.image = image
        self.targetParticleCount = particleCount
        self.config = config

        // Инициализация компонентов
        let performanceParams = config.performanceParams

        self.analyzer = DefaultImageAnalyzer(config: performanceParams)
        self.sampler = DefaultPixelSampler(config: config)
        self.assembler = DefaultParticleAssembler(config: config)
        self.cacheManager = DefaultCacheManager(cacheSizeLimit: performanceParams.cacheSizeLimit * 1024 * 1024)

        // Очищаем кэш при новой конфигурации для применения оптимизаций
        clearCache()

        // Настройка очереди операций
        generationQueue.maxConcurrentOperationCount = 1
        generationQueue.qualityOfService = .userInitiated
        generationQueue.name = "com.particlegen.generation"

        Logger.shared.info("ImageParticleGenerator инициализирован изображением: \(image.width) x \(image.height)")
        Logger.shared.info("Target particles: \(particleCount), quality: \(config.qualityPreset)")
    }

    deinit {
        cancelGeneration()
        Logger.shared.debug("ImageParticleGenerator deinitialized")
    }

    // MARK: - Public API

    /// Генерирует частицы синхронно
    func generateParticles() throws -> [Particle] {
        try generateParticles(screenSize: screenSize)
    }

    /// Генерирует частицы с указанным размером экрана
    func generateParticles(screenSize: CGSize) throws -> [Particle] {
        guard !isGenerating else {
            throw GeneratorError.analysisFailed(reason: "Generation already in progress")
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            // Проверяем кэш
            if config.enableCaching,
               let cached = try cacheManager.retrieve([Particle].self, for: cacheKey()) {
                Logger.shared.debug("Using cached particles")
                stateQueue.async(flags: .barrier) {
                    self.generatedParticles = cached
                }
                return cached
            }

            // Этап 1: Анализ изображения
            updateProgress(0.1, stage: "Анализ изображения")
            let currentAnalysis = try analyzer.analyze(image: image)

            // Этап 2: Сэмплинг пикселей
            updateProgress(0.4, stage: "Сэмплинг пикселей")
            let samples = try sampler.samplePixels(
                from: currentAnalysis,
                targetCount: targetParticleCount,
                config: config,
                image: image
            )

            // Этап 3: Сборка частиц
            updateProgress(0.8, stage: "Сборка частиц")
            let imageSize = CGSize(width: image.width, height: image.height)
            let particles = assembler.assembleParticles(
                from: samples,
                config: config,
                screenSize: screenSize,
                imageSize: imageSize
            )

            // Сохраняем состояние
            stateQueue.async(flags: .barrier) {
                self.analysis = currentAnalysis
                self.generatedParticles = particles
            }

            // Кэшируем результат
            if config.enableCaching {
                try cacheManager.cache(particles, for: cacheKey())
            }

            updateProgress(1.0, stage: "Готово")

            Logger.shared.info("Generated \(particles.count) particles")
            return particles

        } catch {
            updateProgress(0.0, stage: "Ошибка")
            throw error
        }
    }

    /// Генерирует частицы асинхронно
    func generateParticlesAsync(completion: @escaping (Result<[Particle], Error>) -> Void) {
        guard !isGenerating else {
            completion(.failure(GeneratorError.analysisFailed(reason: "Generation already in progress")))
            return
        }

        isGenerating = true

        let operation = AsyncGenerationOperation(
            image: image,
            targetCount: targetParticleCount,
            config: config,
            screenSize: screenSize,
            analyzer: analyzer,
            sampler: sampler,
            assembler: assembler,
            cacheManager: cacheManager,
            cacheKey: cacheKey()
        )

        operation.completionBlock = { [weak self] in
            guard let self = self else { return }

            self.isGenerating = false

            DispatchQueue.main.async {
                if let error = operation.error {
                    self.updateProgress(0.0, stage: "Ошибка")
                    completion(.failure(error))
                } else if let particles = operation.result {
                    self.stateQueue.async(flags: .barrier) {
                        self.generatedParticles = particles
                    }
                    self.updateProgress(1.0, stage: "Готово")
                    completion(.success(particles))
                } else {
                    completion(.failure(GeneratorError.analysisFailed(reason: "Unknown error")))
                }
            }
        }

        operation.progressCallback = { [weak self] progress, stage in
            DispatchQueue.main.async {
                self?.updateProgress(progress, stage: stage)
            }
        }

        currentOperation = operation

        // Запускаем в очереди генерации
        generationQueue.addOperation(operation)
    }

    /// Отменяет текущую генерацию
    func cancelGeneration() {
        generationQueue.cancelAllOperations()
        currentOperation?.cancel()
        isGenerating = false
        updateProgress(0.0, stage: "Отменено")
    }

    /// Обновляет размер экрана
    func updateScreenSize(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else {
            Logger.shared.warning("Invalid screen size: \(size)")
            return
        }

        guard size.width <= 32768, size.height <= 32768 else {
            Logger.shared.warning("Screen size too large: \(size)")
            return
        }

        screenSize = size
    }

    /// Очищает кэш
    func clearCache() {
        cacheManager.clear()
        Logger.shared.debug("Cache cleared")
    }

    // MARK: - ParticleGeneratorDelegate

    func generator(_ generator: ImageParticleGenerator, didUpdateProgress progress: Float, stage: String) {
        delegate?.generator(self, didUpdateProgress: progress, stage: stage)
    }

    func generator(_ generator: ImageParticleGenerator, didEncounterError error: Error) {
        delegate?.generator(self, didEncounterError: error)
    }

    func generatorDidFinish(_ generator: ImageParticleGenerator, particles: [Particle]) {
        delegate?.generatorDidFinish(self, particles: particles)
    }

    // MARK: - Private Methods

    private func updateProgress(_ progress: Float, stage: String) {
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.generator(self, didUpdateProgress: progress, stage: stage)
        }
    }

    private func cacheKey() -> String {
        let components = [
            "\(image.width)x\(image.height)",
            "\(targetParticleCount)",
            "\(config.qualityPreset)",
            "\(config.samplingStrategy)",
            String(format: "%.2f", config.importanceThreshold)
        ]
        return "particles_" + components.joined(separator: "_")
    }
}

// MARK: - Async Operation

private class AsyncGenerationOperation: Operation, @unchecked Sendable {
    private let image: CGImage
    private let targetCount: Int
    private let config: ParticleGenerationConfig
    private let screenSize: CGSize
    private let analyzer: ImageAnalyzer
    private let sampler: PixelSampler
    private let assembler: ParticleAssembler
    private let cacheManager: CacheManager? // weak теперь не нужен, т.к. CacheManager уже AnyObject
    private let cacheKey: String

    private(set) var result: [Particle]?
    private(set) var error: Error?

    var progressCallback: ((Float, String) -> Void)?

    init(image: CGImage, targetCount: Int, config: ParticleGenerationConfig, screenSize: CGSize,
         analyzer: ImageAnalyzer, sampler: PixelSampler, assembler: ParticleAssembler,
         cacheManager: CacheManager, cacheKey: String) {
        self.image = image
        self.targetCount = targetCount
        self.config = config
        self.screenSize = screenSize
        self.analyzer = analyzer
        self.sampler = sampler
        self.assembler = assembler
        self.cacheManager = cacheManager // Store reference normally
        self.cacheKey = cacheKey
    }

    override func main() {
        do {
            // Проверяем кэш
            if config.enableCaching,
               let cached = try cacheManager?.retrieve([Particle].self, for: cacheKey) {
                progressCallback?(1.0, "Загружено из кэша")
                result = cached
                return
            }

            if isCancelled { return }

            // Этап 1: Анализ
            progressCallback?(0.1, "Анализ изображения")
            let analysis = try analyzer.analyze(image: image)

            if isCancelled { return }

            // Этап 2: Сэмплинг
            progressCallback?(0.4, "Сэмплинг пикселей")
            let samples = try sampler.samplePixels(
                from: analysis,
                targetCount: targetCount,
                config: config,
                image: image
            )

            if isCancelled { return }

            // Этап 3: Сборка
            progressCallback?(0.8, "Сборка частиц")
            let imageSize = CGSize(width: image.width, height: image.height)
            let particles = assembler.assembleParticles(
                from: samples,
                config: config,
                screenSize: screenSize,
                imageSize: imageSize
            )

            if isCancelled { return }

            // Кэшируем
            if config.enableCaching {
                try cacheManager?.cache(particles, for: cacheKey)
            }

            result = particles

        } catch {
            if !isCancelled {
                self.error = error
            }
        }
    }

    override func cancel() {
        super.cancel()
        progressCallback?(0.0, "Отменено")
    }
}
