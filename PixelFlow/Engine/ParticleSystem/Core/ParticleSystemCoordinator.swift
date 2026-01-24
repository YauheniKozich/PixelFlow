//
//  ParticleSystemCoordinator.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Главный координатор системы частиц - реализация паттерна Facade
//

import MetalKit
import CoreGraphics

// MARK: - ParticleSystemCoordinator

@MainActor
final class ParticleSystemCoordinator: NSObject,
                                       ParticleSystemCoordinatorProtocol,
                                       @unchecked Sendable {
    
    // MARK: - Immutable dependencies
    
    let renderer: MetalRendererProtocol
    let simulationEngine: SimulationEngineProtocol
    private let storage: ParticleStorageProtocol
    private let generator: ParticleGeneratorProtocol
    private let configManager: ConfigurationManagerProtocol
    private let memoryManager: MemoryManagerProtocol
    private let logger: LoggerProtocol
    private let errorHandler: ErrorHandlerProtocol
    
    // MARK: - State (MainActor‑isolated)
    
    private struct CoordinatorState {
        var particleCount: Int = 0
        var isHighQuality: Bool = false
        var sourceImage: CGImage? = nil
        var isGenerating: Bool = false
        var savedSimulationState: SimulationState? = nil
    }
    private var state = CoordinatorState()
    
    // MARK: - Initialization
    
    init(renderer: MetalRendererProtocol,
         simulationEngine: SimulationEngineProtocol,
         storage: ParticleStorageProtocol,
         configManager: ConfigurationManagerProtocol,
         memoryManager: MemoryManagerProtocol,
         generator: ParticleGeneratorProtocol,
         logger: LoggerProtocol = Logger.shared,
         errorHandler: ErrorHandlerProtocol) {
        
        self.renderer = renderer
        self.simulationEngine = simulationEngine
        self.storage = storage
        self.configManager = configManager
        self.memoryManager = memoryManager
        self.generator = generator
        self.logger = logger
        self.errorHandler = errorHandler
        
        super.init()
        
        renderer.setSimulationEngine(simulationEngine)
        setupCallbacks()
        
        logger.info("ParticleSystemCoordinator initialized")
        generator.clearCache()
        logger.info("Cache cleared on startup")
    }
    
    // MARK: - Simulation
    
    func startSimulation() {
        logger.debug("Starting particle simulation")
        simulationEngine.start()
    }
    
    func stopSimulation() {
        logger.debug("Stopping particle simulation")
        simulationEngine.stop()
    }
    
    func toggleSimulation() {
        switch simulationEngine.state {
        case .chaotic:
            simulationEngine.startCollecting()
        case .collecting, .collected, .lightningStorm:
            simulationEngine.start()
        case .idle:
            simulationEngine.start()
        }
    }
    
    func startLightningStorm() {
        logger.info("Starting lightning storm effect")
        simulationEngine.startLightningStorm()
    }
    
    // MARK: - Generation
    
    func updateConfiguration(_ config: ParticleGenerationConfig) async {
        logger.info("Updating configuration: \(config.qualityPreset)")
        configManager.apply(config)
        await regenerateParticlesIfNeeded()
    }
    
    // MARK: - High-Quality Generation
    
    func replaceWithHighQualityParticles(completion: @escaping (Bool) -> Void) {
        guard let image = state.sourceImage else {
            logger.error("No source image available for high‑quality generation")
            completion(false)
            return
        }
        pauseSimulationDuringGeneration { [weak self] in
            guard let self = self else { return completion(false) }
            Task {
                await self.generateHighQualityParticles(from: image, completion: completion)
            }
        }
    }
    
    // MARK: - FastPreview (low‑quality)
    
    func initializeFastPreview() {
        logger.info("Initializing fast preview")
        storage.createFastPreviewParticles()
        state.isHighQuality = false
        bindBufferToRenderer()
    }
    
    // MARK: - Cleanup
    
    func cleanup() {
        logger.info("Cleaning up particle system")
        stopSimulation()
        renderer.cleanup()
        storage.clear()
        memoryManager.releaseMemory()
        state = CoordinatorState()
    }
    
    // MARK: - Properties (MainActor)
    
    var hasActiveSimulation: Bool { simulationEngine.isActive }
    var isHighQuality: Bool { state.isHighQuality }
    var particleCount: Int { state.particleCount }
    var sourceImage: CGImage? { state.sourceImage }
    var particleBuffer: MTLBuffer? { storage.particleBuffer }
    
    // MARK: - Public Initialization
    
    func initialize(with image: CGImage,
                    particleCount: Int,
                    config: ParticleGenerationConfig) {
        logger.info("Initializing with image: \(image.width)x\(image.height), particles: \(particleCount)")
        state.sourceImage = image
        state.particleCount = particleCount
        storage.initialize(with: particleCount)
        let pixels = extractPixelsFromImage(image)
        storage.setSourcePixels(pixels)
        configManager.apply(config)
        do {
            try renderer.setupBuffers(particleCount: particleCount)
            logger.debug("Metal buffers setup completed")
        } catch {
            logger.error("Failed to setup Metal buffers: \(error)")
        }
        bindBufferToRenderer()
        logger.info("ParticleSystemCoordinator initialization sequence completed")
    }
    
    // MARK: - Private Helpers
    
    private func bindBufferToRenderer() {
        renderer.setParticleBuffer(storage.particleBuffer)
        renderer.updateParticleCount(state.particleCount)
    }
    
    private func generateHighQualityParticles(from image: CGImage, completion: @escaping (Bool) -> Void) async {
        do {
            let config = configManager.currentConfig
            let screenSize = renderer.screenSize
            let particles = try await Task.detached {
                try await self.generator.generateParticles(from: image, config: config, screenSize: screenSize)
            }.value
            guard !Task.isCancelled else {
                logger.info("High‑quality generation cancelled")
                await MainActor.run { completion(false) }
                return
            }
            await MainActor.run {
                storage.saveHighQualityPixels(from: particles)
                storage.recreateHighQualityParticles()
                state.particleCount = particles.count
                state.isHighQuality = true
                bindBufferToRenderer()
                completion(true)
            }
        } catch {
            await MainActor.run { [weak self] in
                self?.errorHandler.handle(
                    error,
                    context: "High‑quality particle generation",
                    recovery: .showToast("Не удалось создать качественные частицы")
                )
                completion(false)
            }
        }
    }
    
    // Безопасное извлечение пикселей из CGImage для fast preview (макс. 5000 пикселей, равномерно по изображению)
    private func extractPixelsFromImage(_ image: CGImage) -> [Pixel] {
        guard let pixelData = image.dataProvider?.data,
              let buffer = CFDataGetBytePtr(pixelData) else {
            logger.warning("Cannot extract pixels from image - no pixel data available")
            return []
        }
        let width = image.width
        let height = image.height
        let bytesPerPixel = 4
        let bytesPerRow = image.bytesPerRow
        var pixels: [Pixel] = []
        let totalPixels = width * height
        let targetCount = min(5000, totalPixels)
        pixels.reserveCapacity(targetCount)
        // Вычисляем шаги по X и Y для равномерной дискретизации
        let stepX = max(1, width / Int(sqrt(Float(targetCount) * Float(width) / Float(height))))
        let stepY = max(1, height / Int(sqrt(Float(targetCount) * Float(height) / Float(width))))
        var count = 0
        for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                let index = y * bytesPerRow + x * bytesPerPixel
                if index + 3 >= CFDataGetLength(pixelData) { continue }
                let b = buffer[index]
                let g = buffer[index + 1]
                let r = buffer[index + 2]
                let a = buffer[index + 3]
                pixels.append(Pixel(x: x, y: y, r: r, g: g, b: b, a: a))
                count += 1
                if count >= targetCount { break }
            }
            if count >= targetCount { break }
        }
        logger.debug("Extracted \(count) pixels from image (\(width)x\(height)) for fast preview")
        return pixels
    }
    
    private func setupCallbacks() {
        simulationEngine.resetCounterCallback = { [weak self] in
            guard let self = self else { return }
            Task { @MainActor in
                self.renderer.resetCollectedCounter()
            }
        }
    }
    
    private func regenerateParticlesIfNeeded() async {
        guard !state.isGenerating, let image = state.sourceImage else { return }
        pauseSimulationDuringGeneration {
            do {
                let config = self.configManager.currentConfig
                let screenSize = self.renderer.screenSize
                _ = try await self.generator.generateParticles(
                    from: image,
                    config: config,
                    screenSize: screenSize
                )
                self.logger.debug("Particles regenerated with new configuration")
            } catch {
                self.logger.error("Failed to regenerate particles: \(error)")
            }
        }
    }
    
    private func pauseSimulationDuringGeneration(_ work: @escaping () async -> Void) {
        guard !state.isGenerating else { return }
        state.isGenerating = true
        state.savedSimulationState = simulationEngine.state
        simulationEngine.stop()
        logger.debug("Simulation paused for particle generation")
        Task {
            await work()
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                switch self.state.savedSimulationState {
                case .chaotic: self.simulationEngine.start()
                case .collecting: self.simulationEngine.startCollecting()
                case .lightningStorm: self.simulationEngine.startLightningStorm()
                case .idle, .collected, .none: self.simulationEngine.start()
                }
                self.logger.debug("Simulation resumed after particle generation")
                self.state.savedSimulationState = nil
                self.state.isGenerating = false
            }
        }
    }
    
    // MARK: - Render loop integration
    /// Вызывается каждый кадр из `MTKViewDelegate.draw(in:)`
    func updateSimulation(deltaTime: Float) {
        let clampedDt = min(deltaTime, 0.02)
        guard !state.isGenerating else { return }
        Task { @MainActor in
            simulationEngine.clock.update()
            simulationEngine.update(deltaTime: clampedDt)
            renderer.updateSimulationParams()
        }
    }
    
    func checkCollectionCompletion() {
        Task { @MainActor in
            renderer.checkCollectionCompletion()
        }
    }
}
