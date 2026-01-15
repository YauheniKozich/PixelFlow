//
//  ImageGenerationIntegrationTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Интеграционные тесты для новой системы генерации частиц
//

import Testing
import CoreGraphics
import Foundation
@testable import PixelFlow

@MainActor
class ImageGenerationIntegrationTests {

    private var container: DIContainer!
    private var coordinator: GenerationCoordinator!
    private var context: GenerationContext!
    private var config: ParticleGenerationConfig!

    init() {
        // Настройка DI контейнера для тестов
        container = DIContainer()
        config = ParticleGenerationConfig.standard

        // Регистрация mock зависимостей
        setupMockDependencies()

        // Создание компонентов
        coordinator = GenerationCoordinatorFactory.makeCoordinator()
        context = GenerationContext()
    }



    @Test func testFullGenerationPipeline() async throws {
        // Given
        let image = createTestImage()
        let config = ParticleGenerationConfig.draft
        var progressUpdates: [(Float, String)] = []

        // When
        let particles = try await coordinator.generateParticles(
            from: image,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { progress, stage in
            progressUpdates.append((progress, stage))
        }

        // Then
        #expect(!particles.isEmpty)
        #expect(particles.count > 0)
        #expect(particles.count <= 10000) // draft limit

        // Проверяем прогресс
        #expect(!progressUpdates.isEmpty)
        #expect(progressUpdates.last?.0 == 1.0) // Завершен
        #expect(progressUpdates.last?.1 == "Completed")
    }

    @Test func testGenerationCancellation() async {
        // Given
        let image = createTestImage()
        let config = ParticleGenerationConfig.high // Более долгая генерация

        // When
        async let generationTask = coordinator.generateParticles(
            from: image,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { _, _ in }

        // Даем небольшую задержку для старта генерации
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 сек

        coordinator.cancelGeneration()

        // Then
        do {
            let _ = try await generationTask
            Issue.record("Generation should have been cancelled")
        } catch {
            // Ожидаем отмену
            #expect(coordinator.currentProgress < 1.0 || !coordinator.isGenerating)
        }
    }

    @Test func testGenerationProgressUpdates() async throws {
        // Given
        let image = createTestImage()
        let config = ParticleGenerationConfig.draft
        var progressValues: [Float] = []

        // When
        let _ = try await coordinator.generateParticles(
            from: image,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { progress, _ in
            progressValues.append(progress)
        }

        // Then
        #expect(!progressValues.isEmpty)
        #expect(progressValues.first == 0.0) // Начинается с 0
        #expect(progressValues.last == 1.0)  // Заканчивается 1.0

        // Проверяем монотонность прогресса
        for i in 1..<progressValues.count {
            #expect(progressValues[i] >= progressValues[i-1])
        }
    }

    @Test func testMultipleConcurrentGenerations() async throws {
        // Given
        let image1 = createTestImage()
        let image2 = createTestImage()
        let config = ParticleGenerationConfig.draft

        // When
        async let particles1 = coordinator.generateParticles(from: image1, config: config, screenSize: CGSize(width: 1920, height: 1080)) { _, _ in }
        async let particles2 = coordinator.generateParticles(from: image2, config: config, screenSize: CGSize(width: 1920, height: 1080)) { _, _ in }

        let (result1, result2) = try await (particles1, particles2)

        // Then
        #expect(!result1.isEmpty)
        #expect(!result2.isEmpty)
        #expect(result1.count != result2.count) // Разные изображения дают разные результаты
    }

    @Test func testGenerationContextState() async throws {
        // Given
        let image = createTestImage()
        let config = ParticleGenerationConfig.standard

        // When
        let _ = try await coordinator.generateParticles(
            from: image,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { _, _ in }

        // Then
        // Контекст должен быть очищен после генерации
        #expect(context.image == nil)
        #expect(context.config == nil)
        #expect(context.analysis == nil)
        #expect(context.samples.isEmpty)
        #expect(context.particles.isEmpty)
        #expect(context.progress == 0.0)
        #expect(context.currentStage == "Idle")
    }

    @Test func testGenerationWithDifferentConfigs() async throws {
        // Given
        let image = createTestImage()
        let configs = [
            ParticleGenerationConfig.draft,
            ParticleGenerationConfig.standard,
            ParticleGenerationConfig.high
        ]

        // When
        var results: [Int] = []
        for config in configs {
            let particles = try await coordinator.generateParticles(from: image, config: config, screenSize: CGSize(width: 1920, height: 1080)) { _, _ in }
            results.append(particles.count)
        }

        // Then
        #expect(results.count == 3)
        // Проверяем что разные конфигурации дают разные количества частиц
        #expect(results[0] != results[1])
        #expect(results[1] != results[2])
    }

    @Test func testErrorHandlingInvalidConfig() async {
        // Given
        let image = createTestImage()
        var config = ParticleGenerationConfig.draft
        config.targetParticleCount = 0 // Invalid config

        // When/Then
        do {
            let _ = try await coordinator.generateParticles(from: image, config: config, screenSize: CGSize(width: 1920, height: 1080)) { _, _ in }
            Issue.record("Should have thrown error for invalid config")
        } catch {
            // Ожидаем ошибку валидации
            #expect(error != nil)
        }
    }

    @Test func testMemoryManagement() async throws {
        // Given
        let image = createTestImage()
        let config = ParticleGenerationConfig.draft

        // When
        let particles = try await coordinator.generateParticles(from: image, config: config, screenSize: CGSize(width: 1920, height: 1080)) { _, _ in }

        // Then
        #expect(!particles.isEmpty)

        // Проверяем что память отслеживается
        let memoryManager: MemoryManagerProtocol? = container.resolve(MemoryManagerProtocol.self)
        #expect(memoryManager?.currentUsage ?? 0 > 0)
    }

    // MARK: - Helper Methods

    private func setupMockDependencies() {
        // Регистрация реальных компонентов для интеграционных тестов
        // (не mock'и, а реальные реализации для проверки интеграции)

        let performanceParams = PerformanceParams(
            maxConcurrentOperations: ProcessInfo.processInfo.activeProcessorCount,
            useSIMD: true,
            enableCaching: true,
            cacheSizeLimit: 100
        )
        container.register(DefaultImageAnalyzer(config: performanceParams), for: ImageAnalyzerProtocol.self)
        container.register(DefaultPixelSampler(config: config), for: PixelSamplerProtocol.self)
        container.register(DefaultParticleAssembler(config: config), for: ParticleAssemblerProtocol.self)
        container.register(DefaultCacheManager(), for: CacheManagerProtocol.self)
        container.register(OperationManager(), for: OperationManagerProtocol.self)
        container.register(MemoryManager(), for: MemoryManagerProtocol.self)
        container.register(Logger.shared, for: LoggerProtocol.self)

        // Регистрация pipeline и coordinator
        let analyzer: ImageAnalyzerProtocol = container.resolve()!
        let sampler: PixelSamplerProtocol = container.resolve()!
        let assembler: ParticleAssemblerProtocol = container.resolve()!
        let operationManager: OperationManagerProtocol = container.resolve()!
        let memoryManager: MemoryManagerProtocol = container.resolve()!
        let cacheManager: CacheManagerProtocol = container.resolve()!
        let logger: LoggerProtocol = container.resolve()!

        let pipeline = GenerationPipeline(analyzer: analyzer, sampler: sampler, assembler: assembler)
        container.register(pipeline, for: GenerationPipelineProtocol.self)

        let coordinator = GenerationCoordinator(
            pipeline: pipeline,
            operationManager: operationManager,
            memoryManager: memoryManager,
            cacheManager: cacheManager,
            logger: logger
        )
        container.register(coordinator, for: GenerationCoordinatorProtocol.self)
    }

    private func createTestImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 100,
            height: 100,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        // Создаем градиент для тестирования
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                    CGColor(red: 0, green: 1, blue: 0, alpha: 1)] as CFArray,
            locations: [0, 1]) {

            context.drawLinearGradient(
                gradient,
                start: CGPoint.zero,
                end: CGPoint(x: 100, y: 100),
                options: []
            )
        }

        return context.makeImage()!
    }
}