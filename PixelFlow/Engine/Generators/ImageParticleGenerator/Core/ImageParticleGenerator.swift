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
#if os(iOS)
import UIKit
#endif

/// Основной класс генератора частиц с модульной архитектурой
final class ImageParticleGenerator: ImageParticleGeneratorProtocol, ParticleGeneratorDelegate {

    // MARK: - Properties

    /// Исходное изображение
    let image: CGImage

    /// Целевое количество частиц
    let targetParticleCount: Int



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
    
    // Новые свойства для ресурсов, которые нужно очищать
    private var pixelCache: PixelCache?
    private var graphicsContext: CGContext?
    private var metalTexture: MTLTexture?
    private var vertexBuffer: MTLBuffer?
    private var pixelData: [UInt8]?
    private var samplesCache: [Sample] = []
    private var dominantColors: [SIMD4<Float>] = []

    private var isGenerating = false
    private var currentOperation: Operation?

    // Прогресс троттлинг
    private var lastProgressUpdate: Float = -1

    // MARK: - Synchronization

    private let stateQueue = DispatchQueue(label: "com.particlegen.state", attributes: .concurrent)
    private let generationQueue = OperationQueue()
    private let cleanupQueue = DispatchQueue(label: "com.particlegen.cleanup", qos: .background)

    // MARK: - Memory Tracking
    
    private var memoryUsage: Int64 = 0
    private var memoryWarningObserver: NSObjectProtocol?

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

        // Настройка очереди операций
        generationQueue.maxConcurrentOperationCount = 1
        generationQueue.qualityOfService = .userInitiated
        generationQueue.name = "com.particlegen.generation"

        // Подписка на уведомления о низкой памяти
        #if os(iOS)
        self.memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleMemoryWarning()
        }
        #endif

        // Очищаем кэш при новой конфигурации для применения оптимизаций
        clearCache()

        Logger.shared.info("ImageParticleGenerator инициализирован изображением: \(image.width) x \(image.height)")
        Logger.shared.info("Target particles: \(particleCount), quality: \(config.qualityPreset)")
    }

    deinit {
        Logger.shared.debug("ImageParticleGenerator deinitialized")
        performCompleteCleanup()
    }

    // MARK: - Public API



    /// Генерирует частицы из изображения
    func generateParticles() throws -> [Particle] {
        // This should not be called since screenSize is only in MetalRenderer
        // But for compatibility, throw error
        throw GeneratorError.analysisFailed(reason: "generateParticles() without screenSize not supported")
    }

    /// Генерирует частицы с указанным размером экрана
    func generateParticles(screenSize: CGSize) throws -> [Particle] {
        // Сброс троттлинга прогресса при старте генерации
        lastProgressUpdate = -1
        guard !isGenerating else {
            throw GeneratorError.analysisFailed(reason: "Generation already in progress")
        }

        isGenerating = true
        defer { isGenerating = false }

        do {
            // Проверяем кэш
            if config.enableCaching,
               let cached = try cacheManager.retrieve([Particle].self, for: cacheKey()) {
                // Проверяем, что количество частиц в кэше соответствует целевому
                if cached.count == targetParticleCount {
                    Logger.shared.debug("Using cached particles")
                    stateQueue.async(flags: .barrier) {
                        self.generatedParticles = cached
                    }
                    return cached
                } else {
                    Logger.shared.debug("Cached particle count (\(cached.count)) doesn't match target (\(targetParticleCount)), regenerating")
                }
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
            Logger.shared.info("ImageParticleGenerator: получено \(samples.count) сэмплов")

            // Этап 3: Сборка частиц
            updateProgress(0.8, stage: "Сборка частиц")
            let imageSize = CGSize(width: image.width, height: image.height)
            let particles = assembler.assembleParticles(
                from: samples,
                config: config,
                screenSize: screenSize,
                imageSize: imageSize,
                originalImageSize: imageSize
            )

            // Добавьте диагностику:
            let imageHeight = Float(image.height)
            let topHalf = particles.filter { $0.position.y < imageHeight / 2 }
            let bottomHalf = particles.filter { $0.position.y >= imageHeight / 2 }
            Logger.shared.debug("Particles distribution - Top: \(topHalf.count), Bottom: \(bottomHalf.count)")
            Logger.shared.debug("Image dimensions: \(image.width)x\(image.height)")
            // Проверяем минимальные и максимальные Y координаты
            let minY = particles.map { $0.position.y }.min() ?? 0
            let maxY = particles.map { $0.position.y }.max() ?? 0
            Logger.shared.debug("Y range: \(minY) - \(maxY) (should be 0 - \(imageHeight))")

            // Сохраняем состояние
            stateQueue.async(flags: .barrier) {
                self.analysis = currentAnalysis
                self.generatedParticles = particles
                self.samplesCache.removeAll(keepingCapacity: true)
                self.samplesCache = samples
                self.dominantColors.removeAll(keepingCapacity: true)
                self.dominantColors = currentAnalysis.dominantColors.map { SIMD4<Float>($0.x, $0.y, $0.z, 1.0) }
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

    /// Отменяет текущую генерацию
    func cancelGeneration() {
        Logger.shared.debug("[ImageParticleGenerator] Отмена генерации")
        
        // Сброс троттлинга прогресса при отмене
        lastProgressUpdate = -1
        generationQueue.cancelAllOperations()
        currentOperation?.cancel()
        currentOperation = nil
        isGenerating = false
        
        // Очищаем промежуточные данные
        cleanupIntermediateData()
        
        updateProgress(0.0, stage: "Отменено")
    }



    /// Очищает кэш
    func clearCache() {
        Logger.shared.debug("[ImageParticleGenerator] Начало очистки кэша")
        
        // 1. Отмена текущих операций
        cancelGeneration()
        
        // 2. Очистка кэш-менеджера
        cacheManager.clear()
        
        // 3. Очистка анализа изображения
        analysis = nil
        
        // 4. Очистка сгенерированных частиц
        stateQueue.async(flags: .barrier) {
            self.generatedParticles.removeAll(keepingCapacity: true)
            self.samplesCache.removeAll(keepingCapacity: true)
            self.dominantColors.removeAll(keepingCapacity: true)
        }
        
        // 5. Очистка PixelCache
        pixelCache = nil
        
        // 6. Очистка графических ресурсов
        graphicsContext = nil
        
        // 7. Очистка Metal ресурсов
        metalTexture = nil
        vertexBuffer = nil
        
        // 8. Очистка пиксельных данных
        pixelData = nil
        
        // 9. Очистка компонентов
        cleanupComponents()
        
        // 10. Сброс состояния генерации
        isGenerating = false
        
        // 11. Освобождение больших буферов
        freeLargeBuffers()
        
        // 12. Обнуление счетчика использования памяти
        memoryUsage = 0
        
        Logger.shared.debug("[ImageParticleGenerator] Кэш полностью очищен")
    }
    
    /// Полная очистка всех ресурсов
    func cleanup() {
        Logger.shared.debug("[ImageParticleGenerator] Полная очистка ресурсов")
        
        // 1. Отмена генерации
        cancelGeneration()
        
        // 2. Очистка кэша
        clearCache()
        
        // 3. Очистка компонентов
        cleanupComponents()
        
        // 4. Очистка очередей
        cleanupQueues()
        
        // 5. Уведомление системы об освобождении памяти
        notifyMemoryRelease()
        
        Logger.shared.debug("[ImageParticleGenerator] Ресурсы очищены")
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
        // Throttle обновления: обновляем только при изменении на >= 0.01
        guard progress - lastProgressUpdate >= 0.01 || progress == 1.0 || progress == 0.0 else { return }
        lastProgressUpdate = progress
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
    
    private func performCompleteCleanup() {
        Logger.shared.debug("[ImageParticleGenerator] Выполнение полной очистки в deinit")
        
        // Отписаться от уведомлений
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Выполнить очистку
        cleanup()
    }
    
    private func cleanupIntermediateData() {
        stateQueue.async(flags: .barrier) {
            // Очищаем только промежуточные данные, не финальные частицы
            self.samplesCache.removeAll(keepingCapacity: true)
            self.dominantColors.removeAll(keepingCapacity: true)
            self.pixelData = nil
        }
    }
    
    private func cleanupComponents() {
        // Если компоненты имеют методы очистки
        if let cleanableAnalyzer = analyzer as? Cleanable {
            cleanableAnalyzer.cleanup()
        }
        if let cleanableSampler = sampler as? Cleanable {
            cleanableSampler.cleanup()
        }
        if let cleanableAssembler = assembler as? Cleanable {
            cleanableAssembler.cleanup()
        }
        if let cleanableCacheManager = cacheManager as? Cleanable {
            cleanableCacheManager.cleanup()
        }
    }
    
    private func cleanupQueues() {
        // Очистка очередей операций
        generationQueue.cancelAllOperations()
        generationQueue.waitUntilAllOperationsAreFinished()
        
        // Очистка очереди состояния
        cleanupQueue.async { [weak self] in
            self?.stateQueue.sync {
                // Дополнительная очистка
            }
        }
    }
    
    private func freeLargeBuffers() {
        // Освобождение больших буферов
        cleanupQueue.async {
            autoreleasepool {
                self.pixelData = nil
                self.vertexBuffer = nil
                self.metalTexture = nil
            }
        }
    }
    
    private func notifyMemoryRelease() {
        // Уведомление системы об освобождении памяти
        cleanupQueue.async {
            if #available(iOS 13.0, *) {
                Task.detached {
                    // Дать время на освобождение
                    try? await Task.sleep(nanoseconds: 50_000_000) // 50ms
                }
            }
        }
    }
    
    private func handleMemoryWarning() {
        Logger.shared.warning("[ImageParticleGenerator] Получено уведомление о низкой памяти")
        
        // Немедленная очистка кэша через cleanupQueue с barrier
        cleanupQueue.async(flags: .barrier) { [weak self] in
            self?.clearCache()
        }
        
        // Принудительный вызов сборщика мусора
        cleanupQueue.async {
            autoreleasepool {
                // Создаем и сразу освобождаем объекты
                let temporaryObjects = [AnyObject]()
                _ = temporaryObjects.count
            }
        }
    }
    
    // MARK: - Memory Tracking
    
    private func updateMemoryUsage() {
        // Оценка использования памяти
        var estimatedUsage: Int64 = 0
        
        // Пиксельные данные
        if let pixelData = pixelData {
            estimatedUsage += Int64(pixelData.count)
        }
        
        // Частицы
        estimatedUsage += Int64(generatedParticles.count * MemoryLayout<Particle>.size)
        
        // Сэмплы
        estimatedUsage += Int64(samplesCache.count * MemoryLayout<Sample>.size)
        
        memoryUsage = estimatedUsage
        
        if memoryUsage > 100 * 1024 * 1024 { // 100MB
            Logger.shared.warning("[ImageParticleGenerator] Высокое использование памяти: \(memoryUsage / (1024 * 1024))MB")
        }
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
    private let cacheManager: CacheManager
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
        self.cacheManager = cacheManager
        self.cacheKey = cacheKey
    }

    override func main() {
        do {
            // Проверяем кэш
            if config.enableCaching,
               let cached = try cacheManager.retrieve([Particle].self, for: cacheKey) {
                // Проверяем, что количество частиц в кэше соответствует целевому
                if cached.count == targetCount {
                    progressCallback?(1.0, "Загружено из кэша")
                    result = cached
                    return
                } else {
                    Logger.shared.debug("Cached particle count (\(cached.count)) doesn't match target (\(targetCount)), regenerating")
                }
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
                imageSize: imageSize,
                originalImageSize: imageSize
            )

            if isCancelled { return }

            // Кэшируем
            if config.enableCaching {
                try cacheManager.cache(particles, for: cacheKey)
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
