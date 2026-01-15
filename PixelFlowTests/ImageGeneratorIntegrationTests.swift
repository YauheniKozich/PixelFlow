//
//  ImageGeneratorIntegrationTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Интеграционные тесты для адаптера и полной системы генерации
//

import XCTest
import CoreGraphics
@testable import PixelFlow

final class ImageGeneratorIntegrationTests: XCTestCase {

    private var container: DIContainer!

    override func setUp() {
        super.setUp()

        // Настройка DI контейнера для тестов генератора
        container = DIContainer()

        // Регистрация зависимостей
        ParticleSystemDependencies.register(in: container)
        ImageGeneratorDependencies.register(in: container)
    }

    override func tearDown() {
        container.reset()
        container = nil
        super.tearDown()
    }

    func testImageParticleGeneratorAdapterCreation() throws {
        // Given
        let image = createTestImage()

        // When
        let adapter = try ImageParticleGeneratorAdapter(image: image, particleCount: 1000)

        // Then
        XCTAssertEqual(adapter.image, image)
    }

    func testAdapterGeneratesParticles() async throws {
        // Given
        let image = createTestImage()
        let adapter = try ImageParticleGeneratorAdapter(image: image, particleCount: 1000)

        // When
        let particles = try await adapter.generateParticles()

        // Then
        XCTAssertFalse(particles.isEmpty)
        XCTAssertGreaterThan(particles.count, 0)
        XCTAssertLessThanOrEqual(particles.count, 1500) // Примерный диапазон

        // Проверяем структуру частиц с реальными свойствами
        for particle in particles {
            XCTAssertGreaterThanOrEqual(particle.size, 0)
            XCTAssertGreaterThanOrEqual(particle.life, 0)
            XCTAssertGreaterThanOrEqual(particle.baseSize, 0)
            
            // Проверяем позиции
            XCTAssertFalse(particle.position.x.isNaN)
            XCTAssertFalse(particle.position.y.isNaN)
            XCTAssertFalse(particle.position.z.isNaN)
            
            // Проверяем цвета
            XCTAssertGreaterThanOrEqual(particle.color.x, 0)
            XCTAssertGreaterThanOrEqual(particle.color.y, 0)
            XCTAssertGreaterThanOrEqual(particle.color.z, 0)
            XCTAssertGreaterThanOrEqual(particle.color.w, 0)
            XCTAssertLessThanOrEqual(particle.color.w, 1) // Alpha в пределах [0,1]
            
            XCTAssertGreaterThanOrEqual(particle.originalColor.x, 0)
            XCTAssertGreaterThanOrEqual(particle.originalColor.y, 0)
            XCTAssertGreaterThanOrEqual(particle.originalColor.z, 0)
            XCTAssertGreaterThanOrEqual(particle.originalColor.w, 0)
        }
    }

    func testAdapterWithDifferentConfigs() async throws {
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
            let adapter = try ImageParticleGeneratorAdapter(image: image, particleCount: 1000, config: config)
            let particles = try await adapter.generateParticles()
            results.append(particles.count)
        }

        // Then
        XCTAssertEqual(results.count, 3)
        // Разные конфигурации могут давать разное количество частиц
        XCTAssertNotEqual(results[0], results[2]) // draft vs high должны отличаться
    }

    func testMigrationHelperCreatesCorrectGenerator() throws {
        // Given
        let image = createTestImage()

        // When
        let generator = try GeneratorMigrationHelper.createGenerator(
            image: image,
            particleCount: 1000,
            config: .standard
        )

        // Then
        XCTAssertTrue(generator is ImageParticleGeneratorAdapter)
    }

    func testGenerationCoordinatorFullIntegration() async throws {
        // Given
        let coordinator: GenerationCoordinatorProtocol = container.resolve()!
        let image = createTestImage()
        let config = ParticleGenerationConfig.standard

        // When
        let particles = try await coordinator.generateParticles(
            from: image,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { progress, stage in
            XCTAssertFalse(stage.isEmpty)
        }

        // Then
        XCTAssertFalse(particles.isEmpty)
        XCTAssertFalse(coordinator.isGenerating)
        XCTAssertEqual(coordinator.currentProgress, 1.0)
        XCTAssertEqual(coordinator.currentStage, "Completed")
    }

    func testGenerationPipelineIntegration() async throws {
        // Given
        let pipeline: GenerationPipelineProtocol = container.resolve()!
        let image = createTestImage()
        let config = ParticleGenerationConfig.standard

        // When
        let particles = try await pipeline.execute(
            image: image,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { progress, stage in
            // Пустой обработчик прогресса для теста
            _ = progress
            _ = stage
        }

        // Then
        XCTAssertFalse(particles.isEmpty)
    }

    func testOperationManagerIntegration() async throws {
        // Given
        let operationManager: OperationManagerProtocol = container.resolve()!

        // When
        let result = try await operationManager.execute {
            try await Task.sleep(nanoseconds: 100_000_000) // 0.1 секунды
            return "test_result"
        }

        // Then
        XCTAssertEqual(result, "test_result")
        XCTAssertFalse(operationManager.hasActiveOperations)
    }

    func testCacheManagerIntegration() async throws {
        // Given
        let cacheManager: CacheManagerProtocol = container.resolve()!
        let testParticles = [createTestParticle()]

        // When
        try cacheManager.cache(testParticles, for: "test_key")

        // Then
        let cached: [Particle]? = try cacheManager.retrieve([Particle].self, for: "test_key")
        XCTAssertNotNil(cached)
        XCTAssertEqual(cached?.count, 1)
        
        // Проверяем, что свойства сохранились
        if let cachedParticle = cached?.first {
            XCTAssertEqual(cachedParticle.position.x, 100)
            XCTAssertEqual(cachedParticle.color.x, 1)
            XCTAssertEqual(cachedParticle.size, 5.0)
        }
    }

    func testConfigurationValidator() throws {
        // Given
        let validator: ConfigurationValidatorProtocol = container.resolve()!

        // When/Then - Valid config
        let validConfig = ParticleGenerationConfig.standard
        XCTAssertNoThrow(try validator.validate(validConfig))

        // Invalid particle count
        var invalidConfig = validConfig
        invalidConfig.targetParticleCount = 0
        XCTAssertThrowsError(try validator.validate(invalidConfig))
    }

    func testResourceTracker() {
        // Given
        let tracker: ResourceTrackerProtocol = container.resolve()!

        // When
        let testObject = NSObject()
        tracker.trackAllocation(testObject, type: "TestObject")
        tracker.trackAllocation(testObject, type: "TestObject")

        // Then
        XCTAssertEqual(tracker.totalTrackedResources, 2)
        XCTAssertEqual(tracker.resourcesByType["TestObject"], 2)

        let report = tracker.resourceReport()
        XCTAssertTrue(report.contains("TestObject"))
        XCTAssertTrue(report.contains("2"))
    }

    func testStrategiesIntegration() {
        // Given
        let strategies: [GenerationStrategyProtocol] = [
            container.resolve(GenerationStrategyProtocol.self, name: "sequential")!,
            container.resolve(GenerationStrategyProtocol.self, name: "parallel")!,
            container.resolve(GenerationStrategyProtocol.self, name: "adaptive")!
        ]
        
        let config = ParticleGenerationConfig.standard
        
        // When/Then
        for strategy in strategies {
            XCTAssertFalse(strategy.canParallelize(.caching)) // Caching никогда не параллелится
            XCTAssertNoThrow(try strategy.validate(config: config))
            XCTAssertGreaterThan(strategy.estimateExecutionTime(for: config), 0)
            XCTAssertTrue(strategy.isOptimal(for: config))
        }
    }

    func testMemoryManagerIntegration() async throws {
        // Given
        let memoryManager: MemoryManagerProtocol = container.resolve()!
        
        // When
        let coordinator: GenerationCoordinatorProtocol = container.resolve()!
        let image = createTestImage()
        let config = ParticleGenerationConfig.standard
        
        let particles = try await coordinator.generateParticles(
            from: image,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { _, _ in }
        
        XCTAssertFalse(particles.isEmpty)
        // Память должна быть отслежена
        XCTAssertGreaterThan(memoryManager.currentUsage, 0)
    }
    
    func testConcurrentGenerations() async throws {
        // Given
        let coordinator: GenerationCoordinatorProtocol = container.resolve()!
        let image1 = createTestImage()
        let image2 = createTestImage()
        let config = ParticleGenerationConfig.draft
        
        // When
        async let particles1 = coordinator.generateParticles(
            from: image1,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { _, _ in }
        
        async let particles2 = coordinator.generateParticles(
            from: image2,
            config: config,
            screenSize: CGSize(width: 1920, height: 1080)
        ) { _, _ in }
        
        let result1 = try await particles1
        let result2 = try await particles2
        
        // Then
        XCTAssertFalse(result1.isEmpty)
        XCTAssertFalse(result2.isEmpty)
    }
    
    func testParticleSerialization() throws {
        // Given
        let originalParticle = createTestParticle()
        
        // When
        let encoder = JSONEncoder()
        let data = try encoder.encode(originalParticle)
        
        let decoder = JSONDecoder()
        let decodedParticle = try decoder.decode(Particle.self, from: data)
        
        // Then
        XCTAssertEqual(originalParticle.position.x, decodedParticle.position.x, accuracy: 0.001)
        XCTAssertEqual(originalParticle.position.y, decodedParticle.position.y, accuracy: 0.001)
        XCTAssertEqual(originalParticle.position.z, decodedParticle.position.z, accuracy: 0.001)
        
        XCTAssertEqual(originalParticle.color.x, decodedParticle.color.x, accuracy: 0.001)
        XCTAssertEqual(originalParticle.color.y, decodedParticle.color.y, accuracy: 0.001)
        XCTAssertEqual(originalParticle.color.z, decodedParticle.color.z, accuracy: 0.001)
        XCTAssertEqual(originalParticle.color.w, decodedParticle.color.w, accuracy: 0.001)
        
        XCTAssertEqual(originalParticle.size, decodedParticle.size, accuracy: 0.001)
        XCTAssertEqual(originalParticle.baseSize, decodedParticle.baseSize, accuracy: 0.001)
        XCTAssertEqual(originalParticle.life, decodedParticle.life, accuracy: 0.001)
    }
    
    // MARK: - Performance Tests
    
    func testGenerationPerformance() {
        // Given
        let coordinator: GenerationCoordinatorProtocol = container.resolve()!
        let image = createTestImage()
        let config = ParticleGenerationConfig.draft
        
        // When
        measure {
            let expectation = self.expectation(description: "Generation completed")
            
            Task {
                do {
                    _ = try await coordinator.generateParticles(
                        from: image,
                        config: config,
                        screenSize: CGSize(width: 1920, height: 1080)
                    ) { _, _ in }
                    expectation.fulfill()
                } catch {
                    XCTFail("Generation failed: \(error)")
                }
            }
            
            waitForExpectations(timeout: 10.0)
        }
    }
    
    // MARK: - Helper Methods
    
    private func createTestImage() -> CGImage {
        let context = CGContext(
            data: nil,
            width: 200,
            height: 200,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        
        // Создаем простой градиент
        if let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [CGColor(red: 1, green: 0, blue: 0, alpha: 1),
                     CGColor(red: 0, green: 0, blue: 1, alpha: 1)] as CFArray,
            locations: [0, 1]) {
            
            context.drawLinearGradient(
                gradient,
                start: CGPoint.zero,
                end: CGPoint(x: 200, y: 200),
                options: []
            )
        }
        
        return context.makeImage()!
    }
    
    private func createTestParticle() -> Particle {
        Particle(
            position: SIMD3<Float>(100, 100, 0),
            velocity: SIMD3<Float>(10, 10, 0),
            targetPosition: SIMD3<Float>(200, 200, 0),
            color: SIMD4<Float>(1, 0.5, 0.2, 1), // Оранжевый
            originalColor: SIMD4<Float>(1, 1, 1, 1), // Белый
            size: 5.0,
            baseSize: 5.0,
            life: 10.0,
            idleChaoticMotion: 1
        )
    }
    
    func testParticleEquality() {
        // Given
        let particle1 = Particle(
            position: SIMD3<Float>(100, 100, 0),
            velocity: SIMD3<Float>(10, 10, 0)
        )
        
        let particle2 = Particle(
            position: SIMD3<Float>(100, 100, 0),
            velocity: SIMD3<Float>(10, 10, 0)
        )
        
        let particle3 = Particle(
            position: SIMD3<Float>(200, 200, 0),
            velocity: SIMD3<Float>(20, 20, 0)
        )
        
        // Then
        // Так как Particle - struct с дефолтным Equatable, можно сравнивать
        XCTAssertEqual(particle1.position, particle2.position)
        XCTAssertEqual(particle1.velocity, particle2.velocity)
        XCTAssertNotEqual(particle1.position, particle3.position)
    }
}
