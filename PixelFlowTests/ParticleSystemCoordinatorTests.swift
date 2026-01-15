//
//  ParticleSystemCoordinatorTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Unit тесты для ParticleSystemCoordinator
//

import Testing
import Metal
import MetalKit
import CoreGraphics
@testable import PixelFlow

struct ParticleSystemCoordinatorTests {
    private var coordinator: ParticleSystemCoordinator!
    private var mockRenderer: MockMetalRenderer!
    private var mockSimulationEngine: MockSimulationEngine!
    private var mockStorage: MockParticleStorage!
    private var mockConfigManager: MockConfigurationManager!
    private var mockMemoryManager: MockMemoryManager!
    private var mockGenerator: MockParticleGenerator!

    init() {
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

    @Test func testStartSimulation() {
        // When
        coordinator.startSimulation()

        // Then
        #expect(mockSimulationEngine.startCalled)
    }

    @Test func testStopSimulation() {
        // When
        coordinator.stopSimulation()

        // Then
        #expect(mockSimulationEngine.stopCalled)
    }

    @Test func testToggleSimulation_WhenActive() {
        // Given
        mockSimulationEngine.isActive = true

        // When
        coordinator.toggleSimulation()

        // Then
        #expect(mockSimulationEngine.stopCalled)
    }

    @Test func testToggleSimulation_WhenInactive() {
        // Given
        mockSimulationEngine.isActive = false

        // When
        coordinator.toggleSimulation()

        // Then
        #expect(mockSimulationEngine.startCalled)
    }

    @Test func testStartLightningStorm() {
        // When
        coordinator.startLightningStorm()

        // Then
        #expect(mockSimulationEngine.lightningStormCalled)
    }

    @Test func testUpdateConfiguration() async {
        // Given
        let config = ParticleGenerationConfig.high

        // When
        await coordinator.updateConfiguration(config)

        // Then
        #expect(mockConfigManager.appliedConfig != nil)
        #expect(mockConfigManager.appliedConfig?.qualityPreset == .high)
    }

    @Test func testConfigure() {
        // Given
        let screenSize = CGSize(width: 1920, height: 1080)

        // When
        coordinator.configure(screenSize: screenSize)

        // Then
        // configure now does nothing, as screenSize is managed in MetalRenderer
        #expect(true) // Just check it doesn't crash
    }

    @Test @MainActor func testInitializeFastPreview() {
        // When
        coordinator.initializeFastPreview()

        // Then
        #expect(mockStorage.createFastPreviewCalled)
        #expect(mockSimulationEngine.startCalled)
        #expect(coordinator.isHighQuality == false)
    }

    @Test @MainActor func testReplaceWithHighQualityParticles() async throws {
        // When
        let success = await withCheckedContinuation { continuation in
            coordinator.replaceWithHighQualityParticles { success in
                continuation.resume(returning: success)
            }
        }

        // Then
        #expect(success)
        #expect(mockStorage.recreateHighQualityCalled)
        #expect(coordinator.isHighQuality == true)
    }

    @Test func testCleanup() {
        // When
        coordinator.cleanup()

        // Then
        #expect(mockSimulationEngine.stopCalled)
        #expect(mockRenderer.cleanupCalled)
        #expect(mockStorage.clearCalled)
        #expect(mockMemoryManager.releaseMemoryCalled)
    }

    @Test func testParticleCount() {
        // Given
        let expectedCount = 1000

        // When
        coordinator.initialize(with: createTestImage(), particleCount: expectedCount, config: .standard)

        // Then
        #expect(coordinator.particleCount == expectedCount)
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

private class MockMetalRenderer: NSObject, MetalRendererProtocol {
    var setupPipelinesCalled = false
    var setupBuffersCalled = false
    var cleanupCalled = false

    let device = MTLCreateSystemDefaultDevice()!
    let commandQueue = MTLCreateSystemDefaultDevice()!.makeCommandQueue()!
    var screenSize: CGSize = CGSize(width: 1920, height: 1080)

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
    func encodeRender(into commandBuffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor) {}
    func setParticleBuffer(_ buffer: MTLBuffer?) {}
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}
    func draw(in view: MTKView) {}
    func cleanup() { cleanupCalled = true }
}

private class MockSimulationEngine: SimulationEngineProtocol, PhysicsEngineProtocol {
    var startCalled = false
    var stopCalled = false
    var collectingCalled = false
    var lightningStormCalled = false
    var isActive = false

    var state: SimulationState = .idle
    var clock: SimulationClockProtocol = MockSimulationClock()
    var resetCounterCallback: (() -> Void)?

    func start() { startCalled = true; isActive = true }
    func stop() { stopCalled = true; isActive = false }
    func startCollecting() { collectingCalled = true }
    func startLightningStorm() { lightningStormCalled = true }
    func updateProgress(_ progress: Float) {}

    func update(deltaTime: Float) {}
    func applyForces() {}
    func reset() {}
}

private class MockSimulationClock: SimulationClockProtocol {
    var time: Float = 0
    var deltaTime: Float = 0

    func update() {}
    func update(with deltaTime: Float) {}
    func reset() {}
}

private class MockParticleStorage: ParticleStorageProtocol {
    var createFastPreviewCalled = false
    var recreateHighQualityCalled = false
    var clearCalled = false

    var particleBuffer: MTLBuffer?
    var particleCount: Int = 0

    func initialize(with particleCount: Int) { self.particleCount = particleCount }
    func createFastPreviewParticles() { createFastPreviewCalled = true }
    func recreateHighQualityParticles() { recreateHighQualityCalled = true }
    func updateParticles(_ particles: [Particle]) {}
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

    func generateParticles(from image: CGImage, config: ParticleGenerationConfig, screenSize: CGSize) async throws -> [Particle] {
        return []
    }

    func clearCache() {}
}