//
//  IntegrationTests.swift
//  PixelFlowTests
//
//  Created by Yauheni Kozich on 11.01.26.
//  Интеграционные тесты для новой архитектуры
//

import Testing
import MetalKit
@testable import PixelFlow

@MainActor
struct IntegrationTests {
    
    // MARK: - Lifecycle
    
    init() {
        // Регистрация зависимостей должна быть выполнена перед тестами
        setupDependencies()
    }
    
    private func setupDependencies() {
        let container = DIContainer.shared
        ParticleSystemDependencies.register(in: container)
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
    
    private func resolve<T>() -> T? {
        return DIContainer.shared.resolve()
    }
    
    // MARK: - Tests
    
    @Test
    func testParticleSystemCoordinatorCreation() {
        // When
        let coordinator = ParticleSystemFactory.makeCoordinator()
        
        // Then
        #expect(coordinator != nil)
        #expect(!coordinator.hasActiveSimulation)
        #expect(!coordinator.isHighQuality)
    }
    
    @Test
    func testCoordinatorWithImageInitialization() {
        // Given
        let coordinator = ParticleSystemFactory.makeCoordinator()
        let image = createTestImage()
        let config = ParticleGenerationConfig.standard
        
        // When
        coordinator.initialize(with: image, particleCount: 1000, config: config)
        
        // Then
        #expect(coordinator.particleCount == 1000)
        #expect(coordinator.sourceImage != nil)
    }
    
    @Test
    func testCoordinatorSimulationLifecycle() {
        // Given
        let coordinator = ParticleSystemFactory.makeCoordinator()
        
        // When/Then
        #expect(!coordinator.hasActiveSimulation)
        
        coordinator.startSimulation()
        #expect(coordinator.hasActiveSimulation)
        
        coordinator.stopSimulation()
        #expect(!coordinator.hasActiveSimulation)
        
        coordinator.toggleSimulation()
        #expect(coordinator.hasActiveSimulation)
        
        coordinator.toggleSimulation()
        #expect(!coordinator.hasActiveSimulation)
    }
    
    @Test
    func testConfigurationManagerIntegration() {
        // Skip if dependency not registered
        guard let configManager: ConfigurationManagerProtocol = resolve() else {
            #expect(Bool(false), "ConfigurationManager not available")
            return
        }
        
        // Given
        let newConfig = ParticleGenerationConfig.high
        
        // When
        configManager.apply(newConfig)
        
        // Then
        #expect(configManager.currentConfig.qualityPreset == .high)
    }
    
    @Test
    func testImageLoaderService() {
        // Skip if dependency not registered
        guard let imageLoader: ImageLoaderProtocol = resolve() else {
            #expect(Bool(false), "ImageLoader not available")
            return
        }
        
        // When
        let image = imageLoader.loadImageWithFallback()
        
        // Then
        #expect(image != nil)
        #expect(image!.width > 0)
        #expect(image!.height > 0)
    }
    
    @Test
    func testMemoryManagerIntegration() {
        // Skip if dependency not registered
        guard let memoryManager: MemoryManagerProtocol = resolve() else {
            #expect(Bool(false), "MemoryManager not available")
            return
        }
        
        // When
        memoryManager.trackMemoryUsage(1024 * 1024) // 1MB
        
        // Then
        #expect(memoryManager.currentUsage == 1024 * 1024)
    }
    
    @Test
    func testParticleStorageInitialization() {
        // Skip if dependency not registered
        guard let storage: ParticleStorageProtocol = resolve() else {
            #expect(Bool(false), "ParticleStorage not available")
            return
        }
        
        // When
        storage.initialize(with: 1000)
        
        // Then
        #expect(storage.particleCount == 1000)
        #expect(storage.particleBuffer != nil)
    }
    
    @Test
    func testMetalRendererSetup() {
        // Skip on CI without Metal support
        guard let device = MTLCreateSystemDefaultDevice() else {
            #expect(Bool(false), "Metal not available")
            return
        }
        
        // Given
        let renderer: MetalRendererProtocol = MetalRenderer(device: device)
        
        // When/Then
        #expect(throws: Never.self) {
            try renderer.setupPipelines()
        }
        #expect(throws: Never.self) {
            try renderer.setupBuffers(particleCount: 1000)
        }
        #expect(renderer.renderPipeline != nil)
        #expect(renderer.computePipeline != nil)
    }
    
    @Test
    func testSimulationEngineStateTransitions() {
        // Skip if dependency not registered
        guard let engine: SimulationEngineProtocol = resolve() else {
            #expect(Bool(false), "SimulationEngine not available")
            return
        }
        
        // When/Then
        #expect(!engine.isActive)
        
        engine.start()
        #expect(engine.isActive)
        
        engine.stop()
        #expect(!engine.isActive)
    }
    
//    @Test
//    func testEndToEndParticleGeneration() {
//        // Skip if dependency not registered
//        guard let generator: ParticleGeneratorProtocol = resolve() else {
//            #expect(Bool(false), "ParticleGenerator not available")
//            return
//        }
//        
//        // Given
//        let image = createTestImage()
//        let config = ParticleGenerationConfig.draft // Fast config for testing
//        
//        // When
//        #expect(throws: Never.self) {
//            let particles = try generator.generateParticles(
//                from: image,
//                config: config,
//                screenSize: CGSize(width: 1920, height: 1080)
//            )
//            
//            // Then
//            #expect(!particles.isEmpty)
//            #expect(particles.count <= 10000) // draft limit
//        }
//    }
}

// MARK: - DIContainer Extension
extension DIContainer {
    static let shared = DIContainer()
    
    func resolve<T>() -> T? {
        // Здесь должна быть реализация resolve из вашей DI системы
        // Это заглушка - замените на вашу реализацию
        return nil
    }
}
