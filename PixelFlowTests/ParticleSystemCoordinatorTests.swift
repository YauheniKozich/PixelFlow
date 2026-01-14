//
//  ParticleSystemCoordinatorTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Unit тесты для ParticleSystemCoordinator
//

import XCTest
import Metal
@testable import PixelFlow

final class ParticleSystemCoordinatorTests: XCTestCase {
    private var coordinator: ParticleSystemCoordinator!
    private var mockRenderer: MockMetalRenderer!
    private var mockSimulationEngine: MockSimulationEngine!
    private var mockStorage: MockParticleStorage!
    private var mockConfigManager: MockConfigurationManager!
    private var mockMemoryManager: MockMemoryManager!
    private var mockGenerator: MockParticleGenerator!

    override func setUp() {
        super.setUp()

        // Создаем моки
        mockRenderer = MockMetalRenderer()
        mockSimulationEngine = MockSimulationEngine()
        mockStorage = MockParticleStorage()
        mockConfigManager = MockConfigurationManager()
        mockMemoryManager = MockMemoryManager()
        mockGenerator = MockParticleGenerator()

        // Создаем координатор с моками
        coordinator = ParticleSystemCoordinator(
            renderer: mockRenderer,
            simulationEngine: mockSimulationEngine,
            storage: mockStorage,
            configManager: mockConfigManager,
            memoryManager: mockMemoryManager,
            generator: mockGenerator
        )
    }

    override func tearDown() {
        coordinator = nil
        mockRenderer = nil
        mockSimulationEngine = nil
        mockStorage = nil
        mockConfigManager = nil
        mockMemoryManager = nil
        mockGenerator = nil
        super.tearDown()
    }

    func testStartSimulation() {
        // When
        coordinator.startSimulation()

        // Then
        XCTAssertTrue(mockSimulationEngine.startCalled)
    }

    func testStopSimulation() {
        // When
        coordinator.stopSimulation()

        // Then
        XCTAssertTrue(mockSimulationEngine.stopCalled)
    }

    func testToggleSimulation_WhenActive() {
        // Given
        mockSimulationEngine.isActive = true

        // When
        coordinator.toggleSimulation()

        // Then
        XCTAssertTrue(mockSimulationEngine.stopCalled)
    }

    func testToggleSimulation_WhenInactive() {
        // Given
        mockSimulationEngine.isActive = false

        // When
        coordinator.toggleSimulation()

        // Then
        XCTAssertTrue(mockSimulationEngine.startCalled)
    }

    func testStartLightningStorm() {
        // When
        coordinator.startLightningStorm()

        // Then
        XCTAssertTrue(mockSimulationEngine.lightningStormCalled)
    }

    func testUpdateConfiguration() {
        // Given
        let config = ParticleGenerationConfig.high

        // When
        coordinator.updateConfiguration(config)

        // Then
        XCTAssertEqual(mockConfigManager.appliedConfig, config)
    }

    func testConfigure() {
        // Given
        let screenSize = CGSize(width: 1920, height: 1080)

        // When
        coordinator.configure(screenSize: screenSize)

        // Then
        XCTAssertTrue(mockRenderer.setupPipelinesCalled)
        XCTAssertTrue(mockRenderer.setupBuffersCalled)
    }

    func testInitializeFastPreview() {
        // When
        coordinator.initializeFastPreview()

        // Then
        XCTAssertTrue(mockStorage.createFastPreviewCalled)
        XCTAssertTrue(mockSimulationEngine.startCalled)
        XCTAssertTrue(coordinator.isHighQuality == false)
    }

    func testReplaceWithHighQualityParticles() {
        // Given
        let expectation = self.expectation(description: "High quality particles replacement")

        // When
        coordinator.replaceWithHighQualityParticles { success in
            XCTAssertTrue(success)
            expectation.fulfill()
        }

        // Then
        waitForExpectations(timeout: 1.0)
        XCTAssertTrue(mockStorage.recreateHighQualityCalled)
        XCTAssertTrue(coordinator.isHighQuality == true)
    }

    func testCleanup() {
        // When
        coordinator.cleanup()

        // Then
        XCTAssertTrue(mockSimulationEngine.stopCalled)
        XCTAssertTrue(mockRenderer.cleanupCalled)
        XCTAssertTrue(mockStorage.clearCalled)
        XCTAssertTrue(mockMemoryManager.releaseMemoryCalled)
    }

    func testParticleCount() {
        // Given
        let expectedCount = 1000

        // When
        coordinator.initialize(with: createTestImage(), particleCount: expectedCount, config: .standard)

        // Then
        XCTAssertEqual(coordinator.particleCount, expectedCount)
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

// MARK: - Mock Classes

private class MockMetalRenderer: MetalRendererProtocol {
    var setupPipelinesCalled = false
    var setupBuffersCalled = false
    var cleanupCalled = false

    let device = MTLCreateSystemDefaultDevice()!
    let commandQueue = MTLCreateSystemDefaultDevice()!.makeCommandQueue()!

    var renderPipeline: MTLRenderPipelineState?
    var computePipeline: MTLComputePipelineState?
    var particleBuffer: MTLBuffer?
    var paramsBuffer: MTLBuffer?
    var collectedCounterBuffer: MTLBuffer?

    func setupPipelines() throws {
        setupPipelinesCalled = true
    }

    func setupBuffers(particleCount: Int) throws {
        setupBuffersCalled = true
    }

    func updateSimulationParams() {}
    func resetCollectedCounter() {}
    func checkCollectionCompletion() {}
    func cleanup() { cleanupCalled = true }
}

private class MockSimulationEngine: SimulationEngineProtocol, PhysicsEngineProtocol {
    var startCalled = false
    var stopCalled = false
    var collectingCalled = false
    var lightningStormCalled = false
    var isActive = false

    var state: SimulationState = .idle

    func start() { startCalled = true; isActive = true }
    func stop() { stopCalled = true; isActive = false }
    func startCollecting() { collectingCalled = true }
    func startLightningStorm() { lightningStormCalled = true }
    func updateProgress(_ progress: Float) {}

    func update(deltaTime: Float) {}
    func applyForces() {}
    func reset() {}
}

private class MockParticleStorage: ParticleStorageProtocol {
    var createFastPreviewCalled = false
    var recreateHighQualityCalled = false
    var clearCalled = false

    var particleBuffer: MTLBuffer?
    var particleCount: Int = 0

    func createFastPreviewParticles() { createFastPreviewCalled = true }
    func recreateHighQualityParticles() { recreateHighQualityCalled = true }
    func clear() { clearCalled = true }
}

private class MockConfigurationManager: ConfigurationManagerProtocol {
    var appliedConfig: ParticleGenerationConfig?

    var currentConfig: ParticleGenerationConfig = .standard

    func apply(_ config: ParticleGenerationConfig) { appliedConfig = config; currentConfig = config }
    func optimalParticleCount(for image: CGImage, preset: QualityPreset) -> Int { 1000 }
    func resetToDefaults() {}
}

private class MockMemoryManager: MemoryManagerProtocol {
    var releaseMemoryCalled = false
    var currentUsage: Int64 = 0

    func trackMemoryUsage(_ bytes: Int64) {}
    func releaseMemory() { releaseMemoryCalled = true }
    func handleLowMemory() {}
}

private class MockParticleGenerator: ParticleGeneratorProtocol {
    var image: CGImage? = nil

    func generateParticles(from image: CGImage, config: ParticleGenerationConfig) throws -> [Particle] {
        return []
    }

    func updateScreenSize(_ size: CGSize) {}
    func clearCache() {}
}