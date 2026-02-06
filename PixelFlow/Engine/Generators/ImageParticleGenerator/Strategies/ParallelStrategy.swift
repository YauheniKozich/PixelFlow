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
         logger: LoggerProtocol) {
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
        guard effectiveConcurrency(for: config) > 1 else {
            throw ParallelStrategyError.insufficientConcurrency
        }
        logger.debug("ParallelStrategy validation passed")
    }

    /// Определяет оптимальное количество потоков для этапа
    func optimalConcurrency(for stage: GenerationStage, config: ParticleGenerationConfig) -> Int {
        let availableConcurrency = min(effectiveConcurrency(for: config), 4) // Максимум 4 потока

        switch stage {
        case .analysis:
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
        let concurrency = Double(effectiveConcurrency(for: config))

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
        let hasConcurrency = effectiveConcurrency(for: config) > 1

        return particleCount > 10000 && hasConcurrency
    }

    // MARK: - Private Methods

    private func effectiveConcurrency(for config: ParticleGenerationConfig) -> Int {
        max(1, min(maxConcurrentOperations, config.maxConcurrentOperations))
    }

    private func estimateImageComplexity(_ config: ParticleGenerationConfig) -> Double {
        var complexity = 1.0

        switch config.samplingStrategy {
        case .importance:
            complexity *= 1.8 // Importance сложнее параллелить
        case .adaptive:
            complexity *= 2.2 // Adaptive самый сложный
        case .hybrid:
            complexity *= 2.0
        default:
            complexity *= 1.0
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
