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
         strategy: GenerationStrategyProtocol = SequentialGenerationStrategy(),
         context: GenerationContextProtocol = GenerationContext(),
         logger: LoggerProtocol = Logger.shared) {

        self.analyzer = analyzer
        self.sampler = sampler
        self.assembler = assembler
        self.strategy = strategy
        self.context = context
        self.logger = logger

        logger.info("GenerationPipeline initialized with strategy: \(type(of: strategy))")
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

        // Выполнение этапов согласно стратегии
        let stages = strategy.executionOrder

        for (index, stage) in stages.enumerated() {
            let stageProgress = Float(index) / Float(stages.count)
            let stageWeight = 1.0 / Float(stages.count)

            do {
                let input = try prepareInput(for: stage)
                let output = try await executeStage(stage, input: input, config: config, screenSize: screenSize)

                try processOutput(output, for: stage)

                // Обновление прогресса
                let currentProgress = stageProgress + stageWeight
                progress(currentProgress, stage.description)

                logger.debug("Completed stage: \(stage)")

            } catch {
                logger.error("Failed to execute stage \(stage): \(error)")
                throw GeneratorError.stageFailed(stage: stage.description, error: error)
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

            let imageSize = CGSize(width: image.width, height: image.height)
            let particles = assembler.assembleParticles(
                from: samples,
                config: config,
                screenSize: screenSize,
                imageSize: imageSize,
                originalImageSize: imageSize
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

        case (.assembly, .particles(let particles)):
            context.particles = particles

        case (.caching, .cached):
            // Ничего не делаем, кэширование в координаторе
            break

        default:
            throw GenerationPipelineError.invalidOutput
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

// MARK: - Default Strategy

struct SequentialGenerationStrategy: GenerationStrategyProtocol {
   
    let executionOrder: [GenerationStage] = [.analysis, .sampling, .assembly, .caching]

    func canParallelize(_ stage: GenerationStage) -> Bool { false }

    func dependencies(for stage: GenerationStage) -> [GenerationStage] {
        switch stage {
        case .analysis: return []
        case .sampling: return [.analysis]
        case .assembly: return [.sampling]
        case .caching: return [.assembly]
        }
    }

    func priority(for stage: GenerationStage) -> Operation.QueuePriority {
        switch stage {
        case .analysis: return .veryHigh
        case .sampling: return .high
        case .assembly: return .normal
        case .caching: return .low
        }
    }

    func validate(config: ParticleGenerationConfig) throws {
        // Sequential strategy всегда валидна
    }

    func estimateExecutionTime(for config: ParticleGenerationConfig) -> TimeInterval {
        let analysisTime = 0.05
        let samplingTime = Double(config.targetParticleCount) * 0.0001
        let assemblyTime = Double(config.targetParticleCount) * 0.00005
        let cachingTime = Double(config.targetParticleCount) * 0.00002
        return analysisTime + samplingTime + assemblyTime + cachingTime
    }

    func isOptimal(for config: ParticleGenerationConfig) -> Bool {
        true // Sequential всегда "оптимальна" для тестов
    }
}
