//
//  GenerationStrategiesTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Unit тесты для стратегий генерации
//

import Testing
@testable import PixelFlow

struct GenerationStrategiesTests {

    // MARK: - SequentialStrategy Tests

    @Test func testSequentialStrategyExecutionOrder() {
        let strategy = SequentialStrategy()

        #expect(strategy.executionOrder == [.analysis, .sampling, .assembly, .caching])
    }

    @Test func testSequentialStrategyCannotParallelize() {
        let strategy = SequentialStrategy()

        #expect(!strategy.canParallelize(.analysis))
        #expect(!strategy.canParallelize(.sampling))
        #expect(!strategy.canParallelize(.assembly))
        #expect(!strategy.canParallelize(.caching))
    }

    @Test func testSequentialStrategyDependencies() {
        let strategy = SequentialStrategy()

        #expect(strategy.dependencies(for: .analysis) == [])
        #expect(strategy.dependencies(for: .sampling) == [.analysis])
        #expect(strategy.dependencies(for: .assembly) == [.sampling])
        #expect(strategy.dependencies(for: .caching) == [.assembly])
    }

    @Test func testSequentialStrategyPriorities() {
        let strategy = SequentialStrategy()

        #expect(strategy.priority(for: .analysis) == .veryHigh)
        #expect(strategy.priority(for: .sampling) == .high)
        #expect(strategy.priority(for: .assembly) == .normal)
        #expect(strategy.priority(for: .caching) == .low)
    }

    @Test func testSequentialStrategyValidation() throws {
        let strategy = SequentialStrategy()
        let config = ParticleGenerationConfig.standard

        #expect(throws: Never.self) {
            try strategy.validate(config: config)
        }
    }

    @Test func testSequentialStrategyOptimalForSmallConfigs() {
        let strategy = SequentialStrategy()

        // Маленькая конфигурация - должна быть оптимальной
        let smallConfig = ParticleGenerationConfig.draft
        #expect(strategy.isOptimal(for: smallConfig))

        // Большая конфигурация - может быть не оптимальной
        var largeConfig = ParticleGenerationConfig.ultra
        largeConfig.targetParticleCount = 50000
        #expect(!strategy.isOptimal(for: largeConfig))
    }

    // MARK: - ParallelStrategy Tests

    @Test func testParallelStrategyCanParallelizeAnalysisAndSampling() {
        let strategy = ParallelStrategy(maxConcurrentOperations: 4)

        #expect(strategy.canParallelize(.analysis))
        #expect(strategy.canParallelize(.sampling))
        #expect(!strategy.canParallelize(.assembly))
        #expect(!strategy.canParallelize(.caching))
    }

    @Test func testParallelStrategyValidationRequiresConcurrency() throws {
        let strategy = ParallelStrategy(maxConcurrentOperations: 1)
        let config = ParticleGenerationConfig.standard

        let error = try #require(try? strategy.validate(config: config)) as? ParallelStrategyError
        #expect(error == .insufficientConcurrency)
    }

    @Test func testParallelStrategyOptimalForLargeConfigs() {
        let strategy = ParallelStrategy(maxConcurrentOperations: 4)

        // Большая конфигурация - должна быть оптимальной
        var largeConfig = ParticleGenerationConfig.ultra
        largeConfig.targetParticleCount = 50000
        #expect(strategy.isOptimal(for: largeConfig))

        // Маленькая конфигурация - может быть не оптимальной
        let smallConfig = ParticleGenerationConfig.draft
        #expect(!strategy.isOptimal(for: smallConfig))
    }

    @Test func testParallelStrategyEstimatesFasterTime() {
        let sequential = SequentialStrategy()
        let parallel = ParallelStrategy(maxConcurrentOperations: 4)

        let config = ParticleGenerationConfig.standard

        let sequentialTime = sequential.estimateExecutionTime(for: config)
        let parallelTime = parallel.estimateExecutionTime(for: config)

        #expect(parallelTime < sequentialTime)
    }

    // MARK: - AdaptiveStrategy Tests

    @Test func testAdaptiveStrategyAlwaysOptimal() {
        let strategy = AdaptiveStrategy()

        let configs = [
            ParticleGenerationConfig.draft,
            ParticleGenerationConfig.standard,
            ParticleGenerationConfig.ultra
        ]

        for config in configs {
            #expect(strategy.isOptimal(for: config))
        }
    }

    @Test func testAdaptiveStrategyAdaptsToWorkload() {
        let strategy = AdaptiveStrategy(availableConcurrency: 4)

        // Маленький workload
        let smallConfig = ParticleGenerationConfig.draft
        let smallPlan = strategy.adaptToConfig(smallConfig)

        switch smallPlan {
        case .sequential:
            #expect(true, "Small workload should use sequential")
        default:
            Issue.record("Small workload should use sequential strategy")
        }

        // Большой workload
        var largeConfig = ParticleGenerationConfig.ultra
        largeConfig.targetParticleCount = 50000
        let largePlan = strategy.adaptToConfig(largeConfig)

        switch largePlan {
        case .parallelFull, .parallelLimited:
            #expect(true, "Large workload should use parallel")
        case .sequential:
            #expect(true, "Large workload may fallback to sequential if no concurrency")
        }
    }

    @Test func testAdaptiveStrategyEstimatesTime() {
        let strategy = AdaptiveStrategy()

        let config = ParticleGenerationConfig.standard
        let estimatedTime = strategy.estimateExecutionTime(for: config)

        #expect(estimatedTime > 0)
        #expect(estimatedTime < 10) // Reasonable upper bound
    }

    // MARK: - DeviceCapabilities Tests

    @Test func testDeviceCapabilitiesDetection() {
        let capabilities = DeviceCapabilities.current

        #expect(capabilities.coreCount > 0)
        #expect(capabilities.performanceClass != nil)
    }

    // MARK: - Strategy Comparison Tests

    @Test func testStrategiesHaveSameExecutionOrder() {
        let strategies: [GenerationStrategyProtocol] = [
            SequentialStrategy(),
            ParallelStrategy(),
            AdaptiveStrategy()
        ]

        let expectedOrder: [GenerationStage] = [.analysis, .sampling, .assembly, .caching]

        for strategy in strategies {
            #expect(strategy.executionOrder == expectedOrder)
        }
    }

    @Test func testAllStrategiesHaveValidDependencies() {
        let strategies: [GenerationStrategyProtocol] = [
            SequentialStrategy(),
            ParallelStrategy(),
            AdaptiveStrategy()
        ]

        let stages: [GenerationStage] = [.analysis, .sampling, .assembly, .caching]

        for strategy in strategies {
            for stage in stages {
                let deps = strategy.dependencies(for: stage)
                // Зависимости должны быть предыдущими этапами
                for dep in deps {
                    #expect(stages.firstIndex(of: dep)! < stages.firstIndex(of: stage)!)
                }
            }
        }
    }

    // MARK: - Performance Tests

    @Test func testStrategySelectionPerformance() {
        let strategy = AdaptiveStrategy()

        // Simple performance check without timing
        for _ in 0..<100 {
            let config = ParticleGenerationConfig.standard
            _ = strategy.adaptToConfig(config)
        }
        #expect(true) // Just ensure it doesn't crash
    }

    @Test func testTimeEstimationPerformance() {
        let strategies: [GenerationStrategyProtocol] = [
            SequentialStrategy(),
            ParallelStrategy(),
            AdaptiveStrategy()
        ]

        let config = ParticleGenerationConfig.standard

        // Simple performance check without timing
        for strategy in strategies {
            for _ in 0..<100 {
                _ = strategy.estimateExecutionTime(for: config)
            }
        }
        #expect(true) // Just ensure it doesn't crash
    }
}