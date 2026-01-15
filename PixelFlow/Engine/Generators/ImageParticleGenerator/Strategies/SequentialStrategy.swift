//
//  SequentialStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Последовательная стратегия генерации частиц
//

import Foundation

/// Последовательная стратегия генерации - все этапы выполняются по порядку
final class SequentialStrategy: GenerationStrategyProtocol {

    // MARK: - Properties

    let executionOrder: [GenerationStage] = [.analysis, .sampling, .assembly, .caching]

    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(logger: LoggerProtocol = Logger.shared) {
        self.logger = logger
    }

    // MARK: - GenerationStrategyProtocol

    func canParallelize(_ stage: GenerationStage) -> Bool {
        false // Последовательная стратегия не параллелит ничего
    }

    func dependencies(for stage: GenerationStage) -> [GenerationStage] {
        switch stage {
        case .analysis:
            return []
        case .sampling:
            return [.analysis]
        case .assembly:
            return [.sampling]
        case .caching:
            return [.assembly]
        }
    }

    func priority(for stage: GenerationStage) -> Operation.QueuePriority {
        switch stage {
        case .analysis:
            return .veryHigh // Анализ - самый важный
        case .sampling:
            return .high // Сэмплинг тоже важен
        case .assembly:
            return .normal // Сборка - стандартный приоритет
        case .caching:
            return .low // Кэширование - низкий приоритет
        }
    }

    func validate(config: ParticleGenerationConfig) throws {
        // Sequential стратегия всегда валидна - не имеет специфических требований
        logger.debug("SequentialStrategy validation passed")
    }

    // MARK: - Public Methods

    /// Описание стратегии для логирования
    func description(for stage: GenerationStage) -> String {
        switch stage {
        case .analysis:
            return "Sequential Analysis"
        case .sampling:
            return "Sequential Sampling"
        case .assembly:
            return "Sequential Assembly"
        case .caching:
            return "Sequential Caching"
        }
    }

    /// Оценивает время выполнения для данной конфигурации
    func estimateExecutionTime(for config: ParticleGenerationConfig) -> TimeInterval {
        // Примерная оценка времени выполнения
        let imageComplexity = estimateImageComplexity(config)
        let particleCount = Double(config.targetParticleCount)

        // Базовое время на этап
        let analysisTime = 0.05 // 50ms на анализ
        let samplingTime = particleCount * 0.0001 * imageComplexity // Зависит от количества частиц
        let assemblyTime = particleCount * 0.00005 // Сборка частиц
        let cachingTime = particleCount * 0.00002 // Кэширование

        return analysisTime + samplingTime + assemblyTime + cachingTime
    }

    /// Определяет оптимальность стратегии для конфигурации
    func isOptimal(for config: ParticleGenerationConfig) -> Bool {
        // Sequential оптимальна для:
        // - Маленьких изображений
        // - Малого количества частиц
        // - Ограниченных ресурсов

        let particleCount = config.targetParticleCount

        return particleCount < 100000
    }

    // MARK: - Private Methods

    private func estimateImageComplexity(_ config: ParticleGenerationConfig) -> Double {
        // Примерная оценка сложности на основе конфигурации
        var complexity = 1.0

        switch config.samplingStrategy {
        case .uniform, .importance, .adaptive, .hybrid, .advanced:
            complexity *= 1.0
        case .importance:
            complexity *= 1.5 // Importance sampling сложнее
        case .adaptive:
            complexity *= 2.0 // Adaptive самый сложный
        case .hybrid:
            complexity *= 1.8
        }

        switch config.qualityPreset {
        case .draft:
            complexity *= 0.5
        case .standard:
            complexity *= 1.0
        case .high:
            complexity *= 1.3
        case .ultra:
            complexity *= 1.8
        }

        return complexity
    }
}
