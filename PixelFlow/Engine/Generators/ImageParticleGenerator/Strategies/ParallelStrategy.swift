//
//  ParallelStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Параллельная стратегия генерации частиц
//

import Foundation

/// Параллельная стратегия генерации - позволяет выполнять независимые этапы параллельно
final class ParallelStrategy: GenerationStrategyProtocol {

    // MARK: - Properties

    let executionOrder: [GenerationStage] = [.analysis, .sampling, .assembly, .caching]

    private let maxConcurrentOperations: Int
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(maxConcurrentOperations: Int = OperationQueue.defaultMaxConcurrentOperationCount,
         logger: LoggerProtocol = Logger.shared) {
        self.maxConcurrentOperations = maxConcurrentOperations
        self.logger = logger
    }

    // MARK: - GenerationStrategyProtocol

    func canParallelize(_ stage: GenerationStage) -> Bool {
        switch stage {
        case .analysis, .sampling:
            return true // Эти этапы можно параллелить
        case .assembly, .caching:
            return false // Эти требуют последовательности
        }
    }

    func dependencies(for stage: GenerationStage) -> [GenerationStage] {
        switch stage {
        case .analysis:
            return [] // Анализ можно начать сразу
        case .sampling:
            return [.analysis] // Сэмплинг зависит от анализа
        case .assembly:
            return [.sampling] // Сборка зависит от сэмплинга
        case .caching:
            return [.assembly] // Кэширование зависит от сборки
        }
    }

    func priority(for stage: GenerationStage) -> Operation.QueuePriority {
        switch stage {
        case .analysis:
            return .veryHigh // Анализ - критично важный
        case .sampling:
            return .high // Сэмплинг тоже важен
        case .assembly:
            return .normal // Сборка - основной процесс
        case .caching:
            return .low // Кэширование - опционально
        }
    }

    func validate(config: ParticleGenerationConfig) throws {
        // Проверяем что есть ресурсы для параллелизма
        guard maxConcurrentOperations > 1 else {
            throw ParallelStrategyError.insufficientConcurrency
        }

        // Для больших изображений параллелизм особенно важен
        let imageSize = config.screenSize.width * config.screenSize.height
        if imageSize > 2000000 && maxConcurrentOperations < 2 { // > 2M pixels
            logger.warning("Large image with low concurrency may be slow")
        }

        logger.debug("ParallelStrategy validation passed")
    }

    // MARK: - Public Methods

    /// Создает группы операций для параллельного выполнения
    func createOperationGroups(for stages: [GenerationStage]) -> [OperationGroup] {
        var groups: [OperationGroup] = []

        // Группа 1: Анализ (может выполняться параллельно с другими анализами)
        let analysisStages = stages.filter { $0 == .analysis }
        if !analysisStages.isEmpty {
            groups.append(OperationGroup(
                stages: analysisStages,
                allowsParallelExecution: true,
                priority: .veryHigh
            ))
        }

        // Группа 2: Сэмплинг (зависит от анализа, но может быть параллельным)
        let samplingStages = stages.filter { $0 == .sampling }
        if !samplingStages.isEmpty {
            groups.append(OperationGroup(
                stages: samplingStages,
                allowsParallelExecution: maxConcurrentOperations > 1,
                priority: .high
            ))
        }

        // Группа 3: Сборка (последовательная)
        let assemblyStages = stages.filter { $0 == .assembly }
        if !assemblyStages.isEmpty {
            groups.append(OperationGroup(
                stages: assemblyStages,
                allowsParallelExecution: false,
                priority: .normal
            ))
        }

        // Группа 4: Кэширование (последовательное, низкий приоритет)
        let cachingStages = stages.filter { $0 == .caching }
        if !cachingStages.isEmpty {
            groups.append(OperationGroup(
                stages: cachingStages,
                allowsParallelExecution: false,
                priority: .low
            ))
        }

        return groups
    }

    /// Определяет оптимальное количество потоков для этапа
    func optimalConcurrency(for stage: GenerationStage, config: ParticleGenerationConfig) -> Int {
        let availableConcurrency = min(maxConcurrentOperations, 4) // Максимум 4 потока

        switch stage {
        case .analysis:
            // Анализ хорошо параллелится для больших изображений
            let imageSize = config.screenSize.width * config.screenSize.height
            if imageSize > 1000000 { // > 1M pixels
                return min(availableConcurrency, 2)
            }
            return 1

        case .sampling:
            // Сэмплинг зависит от количества частиц
            let particleCount = config.targetParticleCount
            if particleCount > 5000 {
                return min(availableConcurrency, 2)
            }
            return 1

        case .assembly, .caching:
            // Эти этапы лучше работают последовательно
            return 1
        }
    }

    /// Оценивает время выполнения с учетом параллелизма
    func estimateExecutionTime(for config: ParticleGenerationConfig) -> TimeInterval {
        let imageComplexity = estimateImageComplexity(config)
        let particleCount = Double(config.targetParticleCount)
        let concurrency = Double(maxConcurrentOperations)

        // Базовое время с учетом параллелизма
        let analysisTime = 0.05 // Анализ минимально параллелится
        let samplingTime = (particleCount * 0.0001 * imageComplexity) / concurrency
        let assemblyTime = particleCount * 0.00005 // Сборка последовательная
        let cachingTime = particleCount * 0.00002 // Кэширование последовательное

        return analysisTime + samplingTime + assemblyTime + cachingTime
    }

    /// Проверяет оптимальность стратегии
    func isOptimal(for config: ParticleGenerationConfig) -> Bool {
        // Parallel оптимальна для:
        // - Больших изображений
        // - Большого количества частиц
        // - Доступных ресурсов для параллелизма

        let particleCount = config.targetParticleCount
        let imageSize = config.screenSize.width * config.screenSize.height
        let hasConcurrency = maxConcurrentOperations > 1

        return (particleCount > 10000 || imageSize > 1000000) && hasConcurrency
    }

    // MARK: - Private Methods

    private func estimateImageComplexity(_ config: ParticleGenerationConfig) -> Double {
        var complexity = 1.0

        switch config.samplingStrategy {
        case .uniform, .importance, .adaptive, .hybrid, .advanced:
            complexity *= 1.0
        case .importance:
            complexity *= 1.8 // Importance сложнее параллелить
        case .adaptive:
            complexity *= 2.2 // Adaptive самый сложный
        case .hybrid:
            complexity *= 2.0
        }

        switch config.qualityPreset {
        case .draft:
            complexity *= 0.6
        case .standard:
            complexity *= 1.0
        case .high:
            complexity *= 1.4
        case .ultra:
            complexity *= 1.9
        }

        return complexity
    }
}

/// Группа операций для параллельного выполнения
struct OperationGroup {
    let stages: [GenerationStage]
    let allowsParallelExecution: Bool
    let priority: Operation.QueuePriority

    var maxConcurrentOperations: Int {
        allowsParallelExecution ? OperationQueue.defaultMaxConcurrentOperationCount : 1
    }
}

// MARK: - Errors

enum ParallelStrategyError: Error {
    case insufficientConcurrency

    var localizedDescription: String {
        switch self {
        case .insufficientConcurrency:
            return "Parallel strategy requires maxConcurrentOperations > 1"
        }
    }
}