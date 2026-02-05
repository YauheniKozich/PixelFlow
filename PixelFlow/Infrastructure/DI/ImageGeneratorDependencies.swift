//
//  ImageGeneratorDependencies.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Регистрация зависимостей для генератора изображений
//

import Foundation
import CoreGraphics

/// Регистрация зависимостей для системы генерации изображений
final class ImageGeneratorDependencies {
    
    /// Регистрирует все зависимости для генератора изображений
    static func register(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        logger.info("Registering ImageGenerator dependencies")
        
        // Регистрация стратегий
        registerStrategies(in: container)
        
        // Регистрация компонентов генерации
        registerGenerationComponents(in: container)
        
        // Регистрация вспомогательных сервисов
        registerSupportServices(in: container)
    }
    
    // MARK: - Private Registration Methods
    
    private static func registerStrategies(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        
        // Sequential стратегия - по умолчанию
        container.register(SequentialStrategy(logger: logger), for: GenerationStrategyProtocol.self, name: "sequential")
        
        // Parallel стратегия
        let parallelStrategy = ParallelStrategy(logger: logger)
        container.register(parallelStrategy, for: GenerationStrategyProtocol.self, name: "parallel")
        
        // Adaptive стратегия - рекомендуемая
        let adaptiveStrategy = AdaptiveStrategy(logger: logger)
        container.register(adaptiveStrategy, for: GenerationStrategyProtocol.self, name: "adaptive")
    }
    
    private static func registerGenerationComponents(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        
        // Анализатор изображений
        let performanceParams = PerformanceParams(
            maxConcurrentOperations: ProcessInfo.processInfo.activeProcessorCount,
            useSIMD: true,
            enableCaching: true,
            cacheSizeLimit: 100
        )
        container.register(DefaultImageAnalyzer(config: performanceParams), for: ImageAnalyzerProtocol.self)
        
        // Сэмплер пикселей
        let config = ParticleGenerationConfig.standard
        container.register(DefaultPixelSampler(config: config), for: PixelSamplerProtocol.self)
        
        // Сборщик частиц
        container.register(DefaultParticleAssembler(config: config), for: ParticleAssemblerProtocol.self)
        
        // Контекст генерации
        container.register(GenerationContext(logger: logger), for: GenerationContextProtocol.self)
        
        // Pipeline генерации с adaptive стратегией
        let analyzer = container.resolve(ImageAnalyzerProtocol.self)!
        let sampler = container.resolve(PixelSamplerProtocol.self)!
        let assembler = container.resolve(ParticleAssemblerProtocol.self)!
        let strategy = container.resolve(GenerationStrategyProtocol.self, name: "adaptive")!
        let context = container.resolve(GenerationContextProtocol.self)!
        
        let pipeline = GenerationPipeline(
            analyzer: analyzer,
            sampler: sampler,
            assembler: assembler,
            strategy: strategy,
            context: context,
            logger: logger
        )
        container.register(pipeline, for: GenerationPipelineProtocol.self)
        
        // Менеджер операций
        container.register(OperationManager(logger: logger), for: OperationManagerProtocol.self)
        
        // Менеджер кэша
        container.register(DefaultCacheManager(cacheSizeLimit: 100 * 1024 * 1024), for: CacheManagerProtocol.self) // 100 MB
        
        // Координатор генерации
        let operationManager = container.resolve(OperationManagerProtocol.self)!
        let memoryManager = container.resolve(MemoryManagerProtocol.self)!
        let cacheManager = container.resolve(CacheManagerProtocol.self)!
        let errorHandler = container.resolve(ErrorHandlerProtocol.self)!
        
        let coordinator = GenerationCoordinator(
            pipeline: pipeline,
            operationManager: operationManager,
            memoryManager: memoryManager,
            cacheManager: cacheManager,
            logger: logger,
            errorHandler: errorHandler
        )
        container.register(coordinator, for: GenerationCoordinatorProtocol.self)
        
        // Адаптер генератора частиц
        container.register(ImageParticleGeneratorToParticleSystemAdapter(coordinator: coordinator, logger: logger), for: ParticleGeneratorProtocol.self)
    }
    
    private static func registerSupportServices(in container: DIContainer) {
        // Метрики генерации
        container.register(GenerationMetrics(), for: GenerationMetricsProtocol.self)
        
        // Валидатор конфигурации
        container.register(ConfigurationValidator(), for: ConfigurationValidatorProtocol.self)
    }
}

// MARK: - Default Implementations

/// Метрики генерации (заглушка для совместимости)
final class GenerationMetrics: GenerationMetricsProtocol {
    var analysisTime: TimeInterval = 0
    var samplingTime: TimeInterval = 0
    var assemblyTime: TimeInterval = 0
    
    var totalTime: TimeInterval { analysisTime + samplingTime + assemblyTime }
    
    var pixelsProcessed: Int64 = 0
    var particlesGenerated: Int = 0
    var peakMemoryUsage: Int64 = 0
    
    func reset() {
        analysisTime = 0
        samplingTime = 0
        assemblyTime = 0
        pixelsProcessed = 0
        particlesGenerated = 0
        peakMemoryUsage = 0
    }
    
    func performanceReport() -> String {
        """
        Generation Performance Report:
        Total Time: \(String(format: "%.3fs", totalTime))
        - Analysis: \(String(format: "%.3fs", analysisTime))
        - Sampling: \(String(format: "%.3fs", samplingTime))
        - Assembly: \(String(format: "%.3fs", assemblyTime))
        Pixels Processed: \(pixelsProcessed)
        Particles Generated: \(particlesGenerated)
        Peak Memory: \(ByteCountFormatter.string(fromByteCount: peakMemoryUsage, countStyle: .memory))
        """
    }
}

/// Валидатор конфигурации генерации
final class ConfigurationValidator: ConfigurationValidatorProtocol {
    var maxImageSize: CGSize { CGSize(width: 16384, height: 16384) }
    var maxParticleCount: Int { 500_000 }
    var minParticleCount: Int { 1_000 }
    
    func validate(_ config: ParticleGenerationConfig) throws {
        guard config.targetParticleCount >= minParticleCount else {
            throw ValidationError.validationInvalidParticleCount("Too few particles: \(config.targetParticleCount)")
        }
        
        guard config.targetParticleCount <= maxParticleCount else {
            throw ValidationError.validationInvalidParticleCount("Too many particles: \(config.targetParticleCount)")
        }
    }
    
    func validate(image: CGImage) throws {
        guard image.width > 0 && image.height > 0 else {
            throw ValidationError.validationInvalidImage("Image has zero size")
        }
        
        guard image.width <= Int(maxImageSize.width) &&
                image.height <= Int(maxImageSize.height) else {
            throw ValidationError.validationInvalidImage("Image too large: \(image.width)x\(image.height)")
        }
    }
    
    func validate(particleCount: Int) throws {
        guard particleCount >= minParticleCount else {
            throw ValidationError.validationInvalidParticleCount("Too few particles")
        }
        
        guard particleCount <= maxParticleCount else {
            throw ValidationError.validationInvalidParticleCount("Too many particles")
        }
    }
    
    func suggestFixes(for config: ParticleGenerationConfig) -> [String] {
        var suggestions: [String] = []
        
        if config.targetParticleCount < minParticleCount {
            suggestions.append("Increase particle count to at least \(minParticleCount)")
        }
        
        if config.targetParticleCount > maxParticleCount {
            suggestions.append("Reduce particle count to maximum \(maxParticleCount)")
        }
        return suggestions
    }
}

/// Трекер ресурсов генерации
final class ResourceTracker: ResourceTrackerProtocol {
    private var trackedResources: [String: Int] = [:]
    private let lock = NSLock()
    
    var totalTrackedResources: Int {
        lock.lock()
        defer { lock.unlock() }
        return trackedResources.values.reduce(0, +)
    }
    
    var resourcesByType: [String: Int] {
        lock.lock()
        defer { lock.unlock() }
        return trackedResources
    }
    
    func trackAllocation(_ resource: AnyObject, type: String) {
        lock.lock()
        defer { lock.unlock() }
        trackedResources[type, default: 0] += 1
    }
    
    func trackDeallocation(_ resource: AnyObject) {
        // Здесь можно добавить дополнительный учет если нужно
    }
    
    func resourceReport() -> String {
        lock.lock()
        defer { lock.unlock() }
        
        let total = totalTrackedResources
        var report = "Resource Tracking Report:\n"
        report += "Total tracked resources: \(total)\n"
        
        for (type, count) in trackedResources.sorted(by: { $0.value > $1.value }) {
            report += "- \(type): \(count)\n"
        }
        
        return report
    }
}
