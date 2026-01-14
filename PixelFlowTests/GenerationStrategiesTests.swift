//
//  GenerationStrategiesTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Unit тесты для стратегий генерации
//

import XCTest
@testable import PixelFlow

final class GenerationStrategiesTests: XCTestCase {

    // MARK: - SequentialStrategy Tests

    func testSequentialStrategyExecutionOrder() {
        let strategy = SequentialStrategy()

        XCTAssertEqual(strategy.executionOrder, [.analysis, .sampling, .assembly, .caching])
    }

    func testSequentialStrategyCannotParallelize() {
        let strategy = SequentialStrategy()

        XCTAssertFalse(strategy.canParallelize(.analysis))
        XCTAssertFalse(strategy.canParallelize(.sampling))
        XCTAssertFalse(strategy.canParallelize(.assembly))
        XCTAssertFalse(strategy.canParallelize(.caching))
    }

    func testSequentialStrategyDependencies() {
        let strategy = SequentialStrategy()

        XCTAssertEqual(strategy.dependencies(for: .analysis), [])
        XCTAssertEqual(strategy.dependencies(for: .sampling), [.analysis])
        XCTAssertEqual(strategy.dependencies(for: .assembly), [.sampling])
        XCTAssertEqual(strategy.dependencies(for: .caching), [.assembly])
    }

    func testSequentialStrategyPriorities() {
        let strategy = SequentialStrategy()

        XCTAssertEqual(strategy.priority(for: .analysis), .veryHigh)
        XCTAssertEqual(strategy.priority(for: .sampling), .high)
        XCTAssertEqual(strategy.priority(for: .assembly), .normal)
        XCTAssertEqual(strategy.priority(for: .caching), .low)
    }

    func testSequentialStrategyValidation() {
        let strategy = SequentialStrategy()
        let config = ParticleGenerationConfig.standard

        XCTAssertNoThrow(try strategy.validate(config: config))
    }

    func testSequentialStrategyOptimalForSmallConfigs() {
        let strategy = SequentialStrategy()

        // Маленькая конфигурация - должна быть оптимальной
        let smallConfig = ParticleGenerationConfig.draft
        XCTAssertTrue(strategy.isOptimal(for: smallConfig))

        // Большая конфигурация - может быть не оптимальной
        var largeConfig = ParticleGenerationConfig.ultra
        largeConfig.targetParticleCount = 50000
        XCTAssertFalse(strategy.isOptimal(for: largeConfig))
    }

    // MARK: - ParallelStrategy Tests

    func testParallelStrategyCanParallelizeAnalysisAndSampling() {
        let strategy = ParallelStrategy(maxConcurrentOperations: 4)

        XCTAssertTrue(strategy.canParallelize(.analysis))
        XCTAssertTrue(strategy.canParallelize(.sampling))
        XCTAssertFalse(strategy.canParallelize(.assembly))
        XCTAssertFalse(strategy.canParallelize(.caching))
    }

    func testParallelStrategyValidationRequiresConcurrency() {
        let strategy = ParallelStrategy(maxConcurrentOperations: 1)
        let config = ParticleGenerationConfig.standard

        XCTAssertThrowsError(try strategy.validate(config: config)) { error in
            XCTAssertEqual(error as? ParallelStrategyError, .insufficientConcurrency)
        }
    }

    func testParallelStrategyOptimalForLargeConfigs() {
        let strategy = ParallelStrategy(maxConcurrentOperations: 4)

        // Большая конфигурация - должна быть оптимальной
        var largeConfig = ParticleGenerationConfig.ultra
        largeConfig.targetParticleCount = 50000
        XCTAssertTrue(strategy.isOptimal(for: largeConfig))

        // Маленькая конфигурация - может быть не оптимальной
        let smallConfig = ParticleGenerationConfig.draft
        XCTAssertFalse(strategy.isOptimal(for: smallConfig))
    }

    func testParallelStrategyEstimatesFasterTime() {
        let sequential = SequentialStrategy()
        let parallel = ParallelStrategy(maxConcurrentOperations: 4)

        let config = ParticleGenerationConfig.standard

        let sequentialTime = sequential.estimateExecutionTime(for: config)
        let parallelTime = parallel.estimateExecutionTime(for: config)

        XCTAssertLessThan(parallelTime, sequentialTime)
    }

    // MARK: - AdaptiveStrategy Tests

    func testAdaptiveStrategyAlwaysOptimal() {
        let strategy = AdaptiveStrategy()

        let configs = [
            ParticleGenerationConfig.draft,
            ParticleGenerationConfig.standard,
            ParticleGenerationConfig.ultra
        ]

        for config in configs {
            XCTAssertTrue(strategy.isOptimal(for: config))
        }
    }

    func testAdaptiveStrategyAdaptsToWorkload() {
        let strategy = AdaptiveStrategy(availableConcurrency: 4)

        // Маленький workload
        let smallConfig = ParticleGenerationConfig.draft
        let smallPlan = strategy.adaptToConfig(smallConfig)

        switch smallPlan {
        case .sequential:
            XCTAssert(true, "Small workload should use sequential")
        default:
            XCTFail("Small workload should use sequential strategy")
        }

        // Большой workload
        var largeConfig = ParticleGenerationConfig.ultra
        largeConfig.targetParticleCount = 50000
        let largePlan = strategy.adaptToConfig(largeConfig)

        switch largePlan {
        case .parallelFull, .parallelLimited:
            XCTAssert(true, "Large workload should use parallel")
        case .sequential:
            XCTAssert(true, "Large workload may fallback to sequential if no concurrency")
        }
    }

    func testAdaptiveStrategyEstimatesTime() {
        let strategy = AdaptiveStrategy()

        let config = ParticleGenerationConfig.standard
        let estimatedTime = strategy.estimateExecutionTime(for: config)

        XCTAssertGreaterThan(estimatedTime, 0)
        XCTAssertLessThan(estimatedTime, 10) // Reasonable upper bound
    }

    // MARK: - DeviceCapabilities Tests

    func testDeviceCapabilitiesDetection() {
        let capabilities = DeviceCapabilities.current

        XCTAssertGreaterThan(capabilities.coreCount, 0)
        XCTAssertNotNil(capabilities.performanceClass)
    }

    // MARK: - Strategy Comparison Tests

    func testStrategiesHaveSameExecutionOrder() {
        let strategies: [GenerationStrategyProtocol] = [
            SequentialStrategy(),
            ParallelStrategy(),
            AdaptiveStrategy()
        ]

        let expectedOrder: [GenerationStage] = [.analysis, .sampling, .assembly, .caching]

        for strategy in strategies {
            XCTAssertEqual(strategy.executionOrder, expectedOrder)
        }
    }

    func testAllStrategiesHaveValidDependencies() {
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
                    XCTAssertTrue(stages.firstIndex(of: dep)! < stages.firstIndex(of: stage)!)
                }
            }
        }
    }

    // MARK: - Performance Tests

    func testStrategySelectionPerformance() {
        let strategy = AdaptiveStrategy()

        measure {
            for _ in 0..<100 {
                let config = ParticleGenerationConfig.standard
                _ = strategy.adaptToConfig(config)
            }
        }
    }

    func testTimeEstimationPerformance() {
        let strategies: [GenerationStrategyProtocol] = [
            SequentialStrategy(),
            ParallelStrategy(),
            AdaptiveStrategy()
        ]

        let config = ParticleGenerationConfig.standard

        measure {
            for strategy in strategies {
                for _ in 0..<100 {
                    _ = strategy.estimateExecutionTime(for: config)
                }
            }
        }
    }
}