//
//  GenerationPipeline.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Конвейер выполнения этапов генерации частиц
//

import CoreGraphics
import Foundation

/// Конвейер выполнения этапов генерации частиц
final class GenerationPipeline: GenerationPipelineProtocol {

    // MARK: - Dependencies

    private let analyzer: ImageAnalyzerProtocol
    private let sampler: PixelSamplerProtocol
    private let assembler: ParticleAssemblerProtocol
    private let strategy: GenerationStrategyProtocol
    private var context: GenerationContextProtocol
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(analyzer: ImageAnalyzerProtocol,
         sampler: PixelSamplerProtocol,
         assembler: ParticleAssemblerProtocol,
         strategy: GenerationStrategyProtocol? = nil,
         context: GenerationContextProtocol,
         logger: LoggerProtocol) {

        self.analyzer = analyzer
        self.sampler = sampler
        self.assembler = assembler
        self.context = context
        self.logger = logger
        let resolvedStrategy = strategy ?? SequentialStrategy(logger: logger)
        self.strategy = resolvedStrategy

        logger.info("GenerationPipeline initialized with strategy: \(type(of: resolvedStrategy))")
    }

    // MARK: - GenerationPipelineProtocol

    func execute(
        image: CGImage,
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        progress: @escaping (Float, String) -> Void
    ) async throws -> [Particle] {

        logger.info("Starting generation pipeline for image \(image.width)x\(image.height)")

        // Валидация входных данных
        try validatePrerequisites(for: config)

        // Инициализация контекста
        context.reset()
        context.image = image
        context.config = config

        // Выполнение этапов согласно стратегии (с учётом зависимостей и параллелизма)
        let stages = effectiveStages(for: config)
        let executionPlan = try buildExecutionPlan(stages: stages, strategy: strategy)
        logger.debug("Execution plan: \(executionPlan.map { $0.map(\.description) })")
        let totalStages = stages.count
        var completedStages = 0

        let reportProgress: (GenerationStage) -> Void = { stage in
            completedStages += 1
            let currentProgress = Float(completedStages) / Float(max(1, totalStages))
            self.context.updateProgress(currentProgress, stage: stage.description)
            progress(currentProgress, stage.description)
        }

        for group in executionPlan {
            try Task.checkCancellation()
            let maxParallel = max(1, min(config.maxConcurrentOperations, group.count))
            if group.count == 1 || maxParallel == 1 {
                for stage in group {
                    try await executeStageAndReport(
                        stage,
                        config: config,
                        screenSize: screenSize,
                        reportProgress: reportProgress
                    )
                }
            } else {
                var startIndex = 0
                while startIndex < group.count {
                    let endIndex = min(startIndex + maxParallel, group.count)
                    let chunk = Array(group[startIndex..<endIndex])
                    try await executeStageGroup(
                        chunk,
                        config: config,
                        screenSize: screenSize,
                        reportProgress: reportProgress
                    )
                    startIndex = endIndex
                }
            }
        }

        // Финализация
        guard !context.particles.isEmpty else {
            throw GeneratorError.stageFailed(stage: "Assembly", error: GenerationPipelineError.emptyResult)
        }

        let particles = context.particles

        logger.info("Generation pipeline completed successfully with \(particles.count) particles")
        return particles
    }

    func executeStage(
        _ stage: GenerationStage,
        input: GenerationStageInput,
        config: ParticleGenerationConfig,
        screenSize: CGSize
    ) async throws -> GenerationStageOutput {

        switch stage {
        case .analysis:
            guard case .image(let image) = input else {
                throw GenerationPipelineError.invalidInput
            }

            let analysis = try analyzer.analyze(image: image)
            return .analysis(analysis)

        case .sampling:
            guard case .analysis(let analysis) = input else {
                throw GenerationPipelineError.invalidInput
            }

            guard let image = context.image else {
                throw GenerationPipelineError.missingImage
            }
            logger.debug("Image available: \(image.width)x\(image.height)")

            let samples = try sampler.samplePixels(
                from: analysis,
                targetCount: context.config?.targetParticleCount ?? 1000,
                config: config,
                image: image
            )
            return .samples(samples)

        case .assembly:
            guard case .samples(let samples) = input else {
                throw GenerationPipelineError.invalidInput
            }

            guard let image = context.image, let config = context.config else {
                throw GenerationPipelineError.invalidContext
            }

            let originalImageSize = CGSize(width: image.width, height: image.height)
            // Use the raw pixel dimensions for display to keep pixel-perfect mapping.
            let imageSize = originalImageSize
            let particles = assembler.assembleParticles(
                from: samples,
                config: config,
                screenSize: screenSize,
                imageSize: imageSize,
                originalImageSize: originalImageSize
            )
            return .particles(particles)

        case .caching:
            // Кэширование обрабатывается в координаторе
            return .cached(true)
        }
    }

    func validatePrerequisites(for config: ParticleGenerationConfig) throws {
        try strategy.validate(config: config)
    }

    func cleanupIntermediateData() {
        context.reset()
        logger.debug("Intermediate data cleaned up")
    }

    // MARK: - Private Methods

    private func prepareInput(for stage: GenerationStage) throws -> GenerationStageInput {
        switch stage {
        case .analysis:
            guard let image = context.image else {
                throw GenerationPipelineError.missingImage
            }
            return .image(image)

        case .sampling:
            guard let analysis = context.analysis else {
                throw GenerationPipelineError.missingAnalysis
            }
            return .analysis(analysis)

        case .assembly:
            guard !context.samples.isEmpty else {
                throw GenerationPipelineError.missingSamples
            }
            let samples = context.samples
            return .samples(samples)

        case .caching:
            guard !context.particles.isEmpty else {
                throw GenerationPipelineError.missingParticles
            }
            let particles = context.particles
            return .particles(particles)
        }
    }

    private func processOutput(_ output: GenerationStageOutput, for stage: GenerationStage) throws {
        switch (stage, output) {
        case (.analysis, .analysis(let analysis)):
            context.analysis = analysis

        case (.sampling, .samples(let samples)):
            context.samples = samples
            if let first = samples.first {
                logger.debug("Sampling produced \(samples.count) samples. First: (\(first.x), \(first.y)) color=\(String(format: "%.2f", first.color.x)),\(String(format: "%.2f", first.color.y)),\(String(format: "%.2f", first.color.z)) a=\(String(format: "%.2f", first.color.w))")
            } else {
                logger.warning("Sampling produced 0 samples")
            }

        case (.assembly, .particles(let particles)):
            context.particles = particles
            if let first = particles.first {
                logger.debug("Assembly produced \(particles.count) particles. First: pos=(\(String(format: "%.3f", first.position.x)), \(String(format: "%.3f", first.position.y))) size=\(String(format: "%.2f", first.size)) a=\(String(format: "%.2f", first.color.w))")
            } else {
                logger.warning("Assembly produced 0 particles")
            }

        case (.caching, .cached):
            // Ничего не делаем, кэширование в координаторе
            break

        default:
            throw GenerationPipelineError.invalidOutput
        }
    }

    // MARK: - Execution Planning

    private func effectiveStages(for config: ParticleGenerationConfig) -> [GenerationStage] {
        let stages = strategy.executionOrder
        guard config.enableCaching else {
            return stages.filter { $0 != .caching }
        }
        return stages
    }

    private func buildExecutionPlan(
        stages: [GenerationStage],
        strategy: GenerationStrategyProtocol
    ) throws -> [[GenerationStage]] {
        let stageSet = Set(stages)
        let stageOrderIndex = Dictionary(uniqueKeysWithValues: stages.enumerated().map { ($0.element, $0.offset) })
        var remaining = stages
        var completed = Set<GenerationStage>()
        var plan: [[GenerationStage]] = []

        while !remaining.isEmpty {
            let ready = stages.filter { stage in
                guard remaining.contains(stage) else { return false }
                let deps = strategy.dependencies(for: stage).filter { stageSet.contains($0) }
                return deps.allSatisfy { completed.contains($0) }
            }

            let sortedReady = ready.sorted { lhs, rhs in
                let lhsPriority = priorityValue(strategy.priority(for: lhs))
                let rhsPriority = priorityValue(strategy.priority(for: rhs))
                if lhsPriority != rhsPriority {
                    return lhsPriority > rhsPriority
                }
                let lhsIndex = stageOrderIndex[lhs] ?? 0
                let rhsIndex = stageOrderIndex[rhs] ?? 0
                return lhsIndex < rhsIndex
            }

            guard let firstReady = sortedReady.first else {
                logger.error("Execution plan unresolved dependencies. Remaining: \(remaining)")
                throw GenerationPipelineError.pipelineInvalidConfiguration
            }

            if !strategy.canParallelize(firstReady) {
                plan.append([firstReady])
                completed.insert(firstReady)
                remaining.removeAll { $0 == firstReady }
                continue
            }

            let parallelStages = sortedReady.filter { strategy.canParallelize($0) }
            plan.append(parallelStages)
            for stage in parallelStages {
                completed.insert(stage)
            }
            remaining.removeAll { parallelStages.contains($0) }
        }

        return plan
    }

    private func priorityValue(_ priority: Operation.QueuePriority) -> Int {
        switch priority {
        case .veryHigh: return 4
        case .high: return 3
        case .normal: return 2
        case .low: return 1
        case .veryLow: return 0
        @unknown default: return 2
        }
    }

    // MARK: - Stage Execution

    private func executeStageAndReport(
        _ stage: GenerationStage,
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        reportProgress: @escaping (GenerationStage) -> Void
    ) async throws {
        do {
            try Task.checkCancellation()
            let input = try prepareInput(for: stage)
            let output = try await executeStage(stage, input: input, config: config, screenSize: screenSize)
            try processOutput(output, for: stage)
            reportProgress(stage)
            logger.debug("Completed stage: \(stage)")
        } catch {
            if Task.isCancelled || error is CancellationError {
                throw GeneratorError.cancelled
            }
            logger.error("Failed to execute stage \(stage): \(error)")
            throw GeneratorError.stageFailed(stage: stage.description, error: error)
        }
    }

    private func executeStageGroup(
        _ stages: [GenerationStage],
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        reportProgress: @escaping (GenerationStage) -> Void
    ) async throws {
        try await withThrowingTaskGroup(of: GenerationStage.self) { group in
            for stage in stages {
                group.addTask { [self] in
                    do {
                        try Task.checkCancellation()
                        let input = try prepareInput(for: stage)
                        let output = try await executeStage(stage, input: input, config: config, screenSize: screenSize)
                        try processOutput(output, for: stage)
                        return stage
                    } catch {
                        if Task.isCancelled || error is CancellationError {
                            throw GeneratorError.cancelled
                        }
                        logger.error("Failed to execute stage \(stage): \(error)")
                        throw GeneratorError.stageFailed(stage: stage.description, error: error)
                    }
                }
            }

            for try await stage in group {
                reportProgress(stage)
                logger.debug("Completed stage: \(stage)")
            }
        }
    }
}



extension GenerationStage {
    var description: String {
        switch self {
        case .analysis: return "Image Analysis"
        case .sampling: return "Pixel Sampling"
        case .assembly: return "Particle Assembly"
        case .caching: return "Result Caching"
        }
    }
}
