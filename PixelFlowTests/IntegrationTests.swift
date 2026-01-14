//
//  IntegrationTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Интеграционные тесты для новой архитектуры
//

import XCTest
import MetalKit
@testable import PixelFlow

final class IntegrationTests: XCTestCase {

    private var container: DIContainer!

    override func setUp() {
        super.setUp()
        container = DIContainer()
        ParticleSystemDependencies.register(in: container)
    }

    override func tearDown() {
        container.reset()
        container = nil
        super.tearDown()
    }

    func testParticleSystemCoordinatorCreation() {
        // When
        let coordinator = ParticleSystemFactory.makeCoordinator()

        // Then
        XCTAssertNotNil(coordinator)
        XCTAssertFalse(coordinator.hasActiveSimulation)
        XCTAssertFalse(coordinator.isHighQuality)
    }

    func testCoordinatorWithImageInitialization() {
        // Given
        let coordinator = ParticleSystemFactory.makeCoordinator()
        let image = createTestImage()
        let config = ParticleGenerationConfig.standard

        // When
        coordinator.initialize(with: image, particleCount: 1000, config: config)

        // Then
        XCTAssertEqual(coordinator.particleCount, 1000)
        XCTAssertNotNil(coordinator.sourceImage)
    }

    func testCoordinatorSimulationLifecycle() {
        // Given
        let coordinator = ParticleSystemFactory.makeCoordinator()

        // When/Then
        XCTAssertFalse(coordinator.hasActiveSimulation)

        coordinator.startSimulation()
        XCTAssertTrue(coordinator.hasActiveSimulation)

        coordinator.stopSimulation()
        XCTAssertFalse(coordinator.hasActiveSimulation)

        coordinator.toggleSimulation()
        XCTAssertTrue(coordinator.hasActiveSimulation)

        coordinator.toggleSimulation()
        XCTAssertFalse(coordinator.hasActiveSimulation)
    }

    func testConfigurationManagerIntegration() {
        // Given
        let configManager: ConfigurationManagerProtocol = resolve()!
        let newConfig = ParticleGenerationConfig.high

        // When
        configManager.apply(newConfig)

        // Then
        XCTAssertEqual(configManager.currentConfig.qualityPreset, .high)
    }

    func testImageLoaderService() {
        // Given
        let imageLoader: ImageLoaderProtocol = resolve()!

        // When
        let image = imageLoader.loadImageWithFallback()

        // Then
        XCTAssertNotNil(image)
        XCTAssertTrue(image!.width > 0)
        XCTAssertTrue(image!.height > 0)
    }

    func testMemoryManagerIntegration() {
        // Given
        let memoryManager: MemoryManagerProtocol = resolve()!

        // When
        memoryManager.trackMemoryUsage(1024 * 1024) // 1MB

        // Then
        XCTAssertEqual(memoryManager.currentUsage, 1024 * 1024)
    }

    func testParticleStorageInitialization() {
        // Given
        let storage: ParticleStorageProtocol = resolve()!

        // When
        storage.initialize(with: 1000)

        // Then
        XCTAssertEqual(storage.particleCount, 1000)
        XCTAssertNotNil(storage.particleBuffer)
    }

    func testMetalRendererSetup() {
        // Skip on CI without Metal support
        guard let device = MTLCreateSystemDefaultDevice() else {
            XCTSkip("Metal not available")
            return
        }

        // Given
        let renderer: MetalRendererProtocol = MetalRenderer(device: device)

        // When/Then
        XCTAssertNoThrow(try renderer.setupPipelines())
        XCTAssertNoThrow(try renderer.setupBuffers(particleCount: 1000))
        XCTAssertNotNil(renderer.renderPipeline)
        XCTAssertNotNil(renderer.computePipeline)
    }

    func testSimulationEngineStateTransitions() {
        // Given
        let engine: SimulationEngineProtocol = resolve()!

        // When/Then
        XCTAssertFalse(engine.isActive)

        engine.start()
        XCTAssertTrue(engine.isActive)

        engine.stop()
        XCTAssertFalse(engine.isActive)
    }

    func testEndToEndParticleGeneration() {
        // Given
        let generator: ParticleGeneratorProtocol = resolve()!
        let image = createTestImage()
        let config = ParticleGenerationConfig.draft // Fast config for testing

        // When
        XCTAssertNoThrow(try {
            let particles = try generator.generateParticles(from: image, config: config)

            // Then
            XCTAssertFalse(particles.isEmpty)
            XCTAssertLessThanOrEqual(particles.count, 10000) // draft limit
        })
    }

    // MARK: - Helper Methods

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

        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 100, height: 100))

        return context.makeImage()!
    }
}