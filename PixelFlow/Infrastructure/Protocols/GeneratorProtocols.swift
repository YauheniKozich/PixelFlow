//
//  GeneratorProtocols.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Протоколы для компонентов генераторов частиц
//

import CoreGraphics
import Foundation
import simd

protocol ParticleGenerationServiceProtocol {
    /// Генерирует частицы асинхронно
    func generateParticles(
        from image: CGImage,
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        progress: @escaping (Float, String) -> Void
    ) async throws -> [Particle]

    /// Отменяет генерацию
    func cancelGeneration()

    /// Очищает кэш
    func clearCache()

    /// Активна ли генерация
    var isGenerating: Bool { get }
}

/// Протокол для анализатора изображений
protocol ImageAnalyzerProtocol {
    /// Анализирует изображение
    func analyze(image: CGImage) throws -> ImageAnalysis

    /// Поддерживает ли анализатор SIMD
    var supportsSIMD: Bool { get }

    /// Поддерживает ли анализатор concurrency
    var supportsConcurrency: Bool { get }
}

/// Протокол для сэмплера пикселей
protocol PixelSamplerProtocol {
    /// Выбирает пиксели из анализа
    func samplePixels(
        from analysis: ImageAnalysis,
        targetCount: Int,
        config: ParticleGenerationConfig,
        image: CGImage
    ) throws -> [Sample]

    /// Стратегия сэмплинга
    var samplingStrategy: SamplingStrategy { get }

    /// Поддерживает ли сэмплер адаптивное сэмплинг
    var supportsAdaptiveSampling: Bool { get }
}

/// Протокол для сборщика частиц
protocol ParticleAssemblerProtocol {
    /// Собирает частицы из сэмплов
    func assembleParticles(
        from samples: [Sample],
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        imageSize: CGSize,
        originalImageSize: CGSize
    ) -> [Particle]

    /// Валидирует частицы
   // func validateParticles(_ particles: [Particle]) -> Bool

    /// Размер частиц по умолчанию
 //   var defaultParticleSize: Float { get }
}

/// Протокол для менеджера кэша
protocol CacheManagerProtocol {
    /// Сохраняет объект в кэш
    func cache<T: Codable>(_ object: T, for key: String) throws

    /// Извлекает объект из кэша
    func retrieve<T: Codable>(_ type: T.Type, for key: String) throws -> T?

    /// Проверяет наличие объекта в кэше
    func contains(key: String) -> Bool

    /// Очищает кэш
    func clear()

    /// Размер кэша в байтах
    var size: Int64 { get }

    /// Лимит размера кэша
    var sizeLimit: Int64 { get set }

    /// Количество объектов в кэше
    var count: Int { get }
}

/// Протокол для менеджера операций
protocol OperationManagerProtocol {
    /// Добавляет операцию
    func addOperation(_ operation: Operation)
    
    func execute<T: Sendable>(_ operation: @escaping () async throws -> T) async throws -> T

    /// Отменяет все операции
    func cancelAllOperations()

    /// Ожидает завершения всех операций
    func waitUntilAllOperationsAreFinished()

    /// Максимальное количество одновременных операций
    var maxConcurrentOperationCount: Int { get set }

    /// Качество обслуживания
    var qualityOfService: QualityOfService { get set }

    /// Название очереди
    var name: String? { get set }

    /// Количество операций в очереди
    var operationCount: Int { get }

    /// Количество выполняющихся операций
    var executingOperationsCount: Int { get }
    
    var hasActiveOperations: Bool { get }
}

/// Протокол для трекера ресурсов
protocol ResourceTrackerProtocol {
    /// Отслеживает выделение ресурса
    func trackAllocation(_ resource: AnyObject, type: String)

    /// Отслеживает освобождение ресурса
    func trackDeallocation(_ resource: AnyObject)

    /// Отчет об использовании ресурсов
    func resourceReport() -> String

    /// Общее количество отслеживаемых ресурсов
    var totalTrackedResources: Int { get }

    /// Ресурсы по типам
    var resourcesByType: [String: Int] { get }
}

/// Протокол для фабрики компонентов генератора
protocol GeneratorComponentFactoryProtocol {
    /// Создает анализатор изображений
    func makeImageAnalyzer(config: PerformanceParams) -> ImageAnalyzerProtocol

    /// Создает сэмплер пикселей
    func makePixelSampler(config: ParticleGenerationConfig) -> PixelSamplerProtocol

    /// Создает сборщик частиц
    func makeParticleAssembler(config: ParticleGenerationConfig) -> ParticleAssemblerProtocol

    /// Создает менеджер кэша
    func makeCacheManager(sizeLimit: Int64) -> CacheManagerProtocol

    /// Создает менеджер операций
    func makeOperationManager() -> OperationManagerProtocol

    /// Создает трекер ресурсов
    func makeResourceTracker() -> ResourceTrackerProtocol
}

/// Протокол для контекста генерации
protocol GenerationContextProtocol {
    /// Текущее изображение
    var image: CGImage? { get set }

    /// Конфигурация генерации
    var config: ParticleGenerationConfig? { get set }

    /// Прогресс генерации (0.0 - 1.0)
    var progress: Float { get set }

    /// Текущий этап генерации
    var currentStage: String { get set }

    /// Отменена ли генерация
    var isCancelled: Bool { get set }

    /// Анализ изображения
    var analysis: ImageAnalysis? { get set }

    /// Сэмплы пикселей
    var samples: [Sample] { get set }

    /// Сгенерированные частицы
    var particles: [Particle] { get set }

    /// Сбрасывает контекст для новой генерации
    func reset()

    /// Обновляет прогресс и этап
    func updateProgress(_ progress: Float, stage: String)
}

/// Протокол для делегата генерации частиц
protocol ParticleGenerationDelegate: AnyObject {
    /// Вызывается при обновлении прогресса
    func generation(_ generation: ParticleGenerationServiceProtocol,
                   didUpdateProgress progress: Float,
                   stage: String)

    /// Вызывается при возникновении ошибки
    func generation(_ generation: ParticleGenerationServiceProtocol,
                   didEncounterError error: Error)

    /// Вызывается при успешном завершении
    func generation(_ generation: ParticleGenerationServiceProtocol,
                   didFinishWithParticles particles: [Particle])

    /// Вызывается при отмене генерации
    func generationDidCancel(_ generation: ParticleGenerationServiceProtocol)
}

/// Протокол для метрик генерации
protocol GenerationMetricsProtocol {
    /// Время анализа изображения
    var analysisTime: TimeInterval { get set }

    /// Время сэмплинга
    var samplingTime: TimeInterval { get set }

    /// Время сборки частиц
    var assemblyTime: TimeInterval { get set }

    /// Общее время генерации
    var totalTime: TimeInterval { get }

    /// Количество обработанных пикселей
    var pixelsProcessed: Int64 { get set }

    /// Количество сгенерированных частиц
    var particlesGenerated: Int { get set }

    /// Пиковое использование памяти
    var peakMemoryUsage: Int64 { get set }

    /// Сбрасывает метрики
    func reset()

    /// Создает отчет о производительности
    func performanceReport() -> String
}

/// Протокол для конвейера генерации частиц
protocol GenerationPipelineProtocol {
    /// Выполняет полный цикл генерации частиц
    func execute(
        image: CGImage,
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        progress: @escaping (Float, String) -> Void
    ) async throws -> [Particle]

    /// Выполняет отдельный этап генерации
    func executeStage(
        _ stage: GenerationStage,
        input: GenerationStageInput,
        config: ParticleGenerationConfig,
        screenSize: CGSize
    ) async throws -> GenerationStageOutput

    /// Валидирует предварительные условия
    func validatePrerequisites(for config: ParticleGenerationConfig) throws

    /// Очищает промежуточные данные
    func cleanupIntermediateData()
}

/// Протокол для стратегии генерации
protocol GenerationStrategyProtocol {
    /// Порядок выполнения этапов
    var executionOrder: [GenerationStage] { get }

    /// Можно ли параллелизовать этап
    func canParallelize(_ stage: GenerationStage) -> Bool

    /// Зависимости этапа
    func dependencies(for stage: GenerationStage) -> [GenerationStage]

    /// Приоритет этапа
    func priority(for stage: GenerationStage) -> Operation.QueuePriority

    /// Валидирует конфигурацию для стратегии
    func validate(config: ParticleGenerationConfig) throws

    /// Оценивает время выполнения для конфигурации
    func estimateExecutionTime(for config: ParticleGenerationConfig) -> TimeInterval

    /// Проверяет оптимальность стратегии для конфигурации
    func isOptimal(for config: ParticleGenerationConfig) -> Bool
}

/// Протокол для координатора генерации частиц
protocol GenerationCoordinatorProtocol {
    /// Генерирует частицы асинхронно
    func generateParticles(
        from image: CGImage,
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        progress: @escaping (Float, String) -> Void
    ) async throws -> [Particle]

    /// Отменяет генерацию
    func cancelGeneration()

    /// Активна ли генерация
    var isGenerating: Bool { get }

    /// Текущий прогресс (0.0 - 1.0)
    var currentProgress: Float { get }

    /// Текущий этап генерации
    var currentStage: String { get }
}

/// Этапы генерации частиц
enum GenerationStage {
    case analysis
    case sampling
    case assembly
    case caching
}

/// Входные данные для этапа генерации
enum GenerationStageInput {
    case image(CGImage)
    case analysis(ImageAnalysis)
    case samples([Sample])
    case particles([Particle])
}

/// Выходные данные этапа генерации
enum GenerationStageOutput {
    case analysis(ImageAnalysis)
    case samples([Sample])
    case particles([Particle])
    case cached(Bool)
}

/// Протокол для валидатора конфигурации
protocol ConfigurationValidatorProtocol {
    /// Валидирует конфигурацию генерации
    func validate(_ config: ParticleGenerationConfig) throws

    /// Валидирует изображение
    func validate(image: CGImage) throws

    /// Валидирует количество частиц
    func validate(particleCount: Int) throws

    /// Предлагает исправления для невалидной конфигурации
    func suggestFixes(for config: ParticleGenerationConfig) -> [String]

    /// Максимально допустимый размер изображения
    var maxImageSize: CGSize { get }

    /// Максимально допустимое количество частиц
    var maxParticleCount: Int { get }

    /// Минимально допустимое количество частиц
    var minParticleCount: Int { get }
}

// MARK: - Core Protocols (moved from Core/Protocols.swift)

/// Протокол для анализа изображений (внутренний)
protocol ImageAnalyzer {
    func analyze(image: CGImage) throws -> ImageAnalysis
}

/// Протокол для сэмплинга пикселей (внутренний)
protocol PixelSampler {
    func samplePixels(from analysis: ImageAnalysis, targetCount: Int, config: ParticleGenerationConfig, image: CGImage) throws -> [Sample]
}

/// Протокол для сборки частиц (внутренний)
protocol ParticleAssembler {
    func assembleParticles(from samples: [Sample],
                           config: ParticleGenerationConfig,
                           screenSize: CGSize,
                           imageSize: CGSize,
                           originalImageSize: CGSize) -> [Particle]
}

/// Протокол для кэширования результатов (внутренний)
protocol CacheManager: AnyObject {
    func cache<T: Codable>(_ value: T, for key: String) throws
    func retrieve<T: Codable>(_ type: T.Type, for key: String) throws -> T?
    func clear()
}

/// Протокол для конфигурации генерации (внутренний)
protocol ParticleGeneratorConfiguration: Codable {
    var samplingStrategy: SamplingStrategy { get }
    var qualityPreset: QualityPreset { get }
    var enableCaching: Bool { get }
    var maxConcurrentOperations: Int { get }
}

/// Протокол для расширенной конфигурации генератора с режимом отображения (внутренний)
protocol ParticleGeneratorConfigurationWithDisplayMode: ParticleGeneratorConfiguration {
    var imageDisplayMode: ImageDisplayMode { get }
    var particleLifetime: Float { get }
    var particleSpeed: Float { get }
    var particleSizeUltra: ClosedRange<Float>? { get }
    var particleSizeHigh: ClosedRange<Float>? { get }
    var particleSizeStandard: ClosedRange<Float>? { get }
    var particleSizeLow: ClosedRange<Float>? { get }
}
