//
//  AdaptiveStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Адаптивная стратегия генерации частиц - автоматически выбирает оптимальный подход
//

import Foundation

/// Адаптивная стратегия генерации - анализирует условия и выбирает оптимальный подход
final class AdaptiveStrategy: GenerationStrategyProtocol {

    // MARK: - Properties

    private(set) var executionOrder: [GenerationStage] = [.analysis, .sampling, .assembly, .caching]

    private let availableConcurrency: Int
    private let deviceCapabilities: DeviceCapabilities
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(availableConcurrency: Int = OperationQueue.defaultMaxConcurrentOperationCount,
         deviceCapabilities: DeviceCapabilities = DeviceCapabilities.current,
         logger: LoggerProtocol = Logger.shared) {

        self.availableConcurrency = availableConcurrency
        self.deviceCapabilities = deviceCapabilities
        self.logger = logger
    }

    // MARK: - GenerationStrategyProtocol

    func canParallelize(_ stage: GenerationStage) -> Bool {
        // Адаптивно решаем на основе устройства и данных
        switch stage {
        case .analysis:
            return shouldParallelizeAnalysis()
        case .sampling:
            return shouldParallelizeSampling()
        case .assembly:
            return false // Сборка всегда последовательная
        case .caching:
            return false // Кэширование всегда последовательное
        }
    }

    func dependencies(for stage: GenerationStage) -> [GenerationStage] {
        // Стандартные зависимости
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
        // Динамические приоритеты на основе важности
        switch stage {
        case .analysis:
            return .veryHigh
        case .sampling:
            return .high
        case .assembly:
            return shouldOptimizeForSpeed() ? .high : .normal
        case .caching:
            return shouldSkipCaching() ? .veryLow : .low
        }
    }

    func validate(config: ParticleGenerationConfig) throws {
        // Adaptive стратегия всегда валидна - адаптируется к условиям
        logger.debug("AdaptiveStrategy validation passed - will adapt to conditions")
    }

    // MARK: - Adaptive Logic

    /// Анализирует конфигурацию и выбирает оптимальную стратегию выполнения
    func adaptToConfig(_ config: ParticleGenerationConfig) -> ExecutionPlan {
        let analysis = analyzeWorkload(config)
        let optimalPlan = createExecutionPlan(for: analysis)

        logger.info("Adaptive strategy selected plan: \(optimalPlan.description)")
        return optimalPlan
    }

    private func analyzeWorkload(_ config: ParticleGenerationConfig) -> WorkloadAnalysis {
        let imageSize = config.screenSize.width * config.screenSize.height
        let particleCount = config.targetParticleCount
        let complexity = estimateComplexity(config)

        // Определяем тип workload
        let workloadType: WorkloadType
        if imageSize > 2000000 || particleCount > 20000 { // Большой workload
            workloadType = .heavy
        } else if imageSize > 500000 || particleCount > 5000 { // Средний workload
            workloadType = .medium
        } else { // Маленький workload
            workloadType = .light
        }

        return WorkloadAnalysis(
            type: workloadType,
            imageSize: imageSize,
            particleCount: particleCount,
            complexity: complexity,
            availableConcurrency: availableConcurrency,
            deviceCapabilities: deviceCapabilities
        )
    }

    private func createExecutionPlan(for analysis: WorkloadAnalysis) -> ExecutionPlan {
        switch analysis.type {
        case .light:
            return ExecutionPlan.sequential(
                reason: "Light workload - sequential is fastest",
                estimatedTime: estimateSequentialTime(analysis)
            )

        case .medium:
            if analysis.availableConcurrency > 1 {
                return ExecutionPlan.parallelLimited(
                    maxConcurrency: 2,
                    reason: "Medium workload with available concurrency",
                    estimatedTime: estimateParallelTime(analysis, concurrency: 2)
                )
            } else {
                return ExecutionPlan.sequential(
                    reason: "Medium workload but no concurrency available",
                    estimatedTime: estimateSequentialTime(analysis)
                )
            }

        case .heavy:
            if analysis.availableConcurrency >= 3 {
                return ExecutionPlan.parallelFull(
                    reason: "Heavy workload with high concurrency",
                    estimatedTime: estimateParallelTime(analysis, concurrency: analysis.availableConcurrency)
                )
            } else if analysis.availableConcurrency >= 2 {
                return ExecutionPlan.parallelLimited(
                    maxConcurrency: 2,
                    reason: "Heavy workload with limited concurrency",
                    estimatedTime: estimateParallelTime(analysis, concurrency: 2)
                )
            } else {
                return ExecutionPlan.sequential(
                    reason: "Heavy workload but insufficient concurrency - consider upgrading device",
                    estimatedTime: estimateSequentialTime(analysis)
                )
            }
        }
    }

    // MARK: - Decision Helpers

    private func shouldParallelizeAnalysis() -> Bool {
        // Анализ можно параллелить если:
        // - Доступна concurrency
        // - Устройство поддерживает многопоточность
        availableConcurrency > 1 && deviceCapabilities.supportsConcurrency
    }

    private func shouldParallelizeSampling() -> Bool {
        // Сэмплинг можно параллелить если:
        // - Доступна concurrency
        // - Не слишком много overhead
        availableConcurrency > 1
    }

    private func shouldOptimizeForSpeed() -> Bool {
        // Оптимизация для скорости если:
        // - Есть доступная concurrency
        // - Устройство производительный
        availableConcurrency > 1 && deviceCapabilities.performanceClass == .high
    }

    private func shouldSkipCaching() -> Bool {
        // Пропускаем кэширование если:
        // - Мало памяти
        // - Кэш отключен в настройках
        !deviceCapabilities.hasSufficientMemory
    }

    // MARK: - Estimation Methods

    private func estimateSequentialTime(_ analysis: WorkloadAnalysis) -> TimeInterval {
        let baseTime = Double(analysis.particleCount) * 0.0001 * analysis.complexity
        return baseTime + 0.1 // Overhead
    }

    private func estimateParallelTime(_ analysis: WorkloadAnalysis, concurrency: Int) -> TimeInterval {
        let sequentialTime = estimateSequentialTime(analysis)
        let speedup = min(Double(concurrency), 2.5) // Максимум 2.5x speedup
        let parallelTime = sequentialTime / speedup
        return parallelTime + 0.05 // Parallel overhead
    }

    private func estimateComplexity(_ config: ParticleGenerationConfig) -> Double {
        var complexity = 1.0

        // Sampling strategy impact
        switch config.samplingStrategy {
        case .uniform: complexity *= 1.0
        case .importance: complexity *= 1.2
        case .adaptive: complexity *= 1.3
        case .hybrid: complexity *= 1.5
        case .advanced: complexity *= 1.8
        case .importance: complexity *= 1.5
        case .adaptive: complexity *= 2.0
        case .hybrid: complexity *= 1.8
        }

        // Quality preset impact
        switch config.qualityPreset {
        case .draft: complexity *= 0.5
        case .standard: complexity *= 1.0
        case .high: complexity *= 1.4
        case .ultra: complexity *= 1.8
        }

        return complexity
    }

    func estimateExecutionTime(for config: ParticleGenerationConfig) -> TimeInterval {
        let analysis = analyzeWorkload(config)
        let plan = createExecutionPlan(for: analysis)
        return plan.estimatedTime
    }

    func isOptimal(for config: ParticleGenerationConfig) -> Bool {
        // Adaptive стратегия всегда "оптимальна" - она адаптируется
        true
    }
}

// MARK: - Supporting Types

/// Возможности устройства
struct DeviceCapabilities {
    let supportsConcurrency: Bool
    let performanceClass: PerformanceClass
    let hasSufficientMemory: Bool
    let coreCount: Int

    static var current: DeviceCapabilities {
        let processInfo = ProcessInfo.processInfo
        let coreCount = processInfo.activeProcessorCount

        return DeviceCapabilities(
            supportsConcurrency: coreCount > 1,
            performanceClass: coreCount >= 4 ? .high : (coreCount >= 2 ? .medium : .low),
            hasSufficientMemory: true, // В реальности проверять доступную память
            coreCount: coreCount
        )
    }
}

enum PerformanceClass {
    case low, medium, high
}

/// Анализ workload
struct WorkloadAnalysis {
    let type: WorkloadType
    let imageSize: CGFloat
    let particleCount: Int
    let complexity: Double
    let availableConcurrency: Int
    let deviceCapabilities: DeviceCapabilities
}

enum WorkloadType {
    case light, medium, heavy
}

/// План выполнения
enum ExecutionPlan {
    case sequential(reason: String, estimatedTime: TimeInterval)
    case parallelLimited(maxConcurrency: Int, reason: String, estimatedTime: TimeInterval)
    case parallelFull(reason: String, estimatedTime: TimeInterval)

    var estimatedTime: TimeInterval {
        switch self {
        case .sequential(_, let time): return time
        case .parallelLimited(_, _, let time): return time
        case .parallelFull(_, let time): return time
        }
    }

    var description: String {
        switch self {
        case .sequential(let reason, let time):
            return "Sequential (\(String(format: "%.2fs", time))) - \(reason)"
        case .parallelLimited(let max, let reason, let time):
            return "Parallel(limited:\(max)) (\(String(format: "%.2fs", time))) - \(reason)"
        case .parallelFull(let reason, let time):
            return "Parallel(full) (\(String(format: "%.2fs", time))) - \(reason)"
        }
    }
}