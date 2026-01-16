//
//  ParticleSystemCoordinator.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Главный координатор системы частиц - реализация паттерна Facade
//

import MetalKit
import CoreGraphics

/// Главный координатор системы частиц
/// Управляет взаимодействием между всеми компонентами
final class ParticleSystemCoordinator: NSObject, ParticleSystemCoordinatorProtocol {
   
    // MARK: - Dependencies

    private(set) var renderer: MetalRendererProtocol
    private(set) var simulationEngine: SimulationEngineProtocol
    private let storage: ParticleStorageProtocol
    private(set) var configManager: ConfigurationManagerProtocol
    private let memoryManager: MemoryManagerProtocol
    private let generator: ParticleGeneratorProtocol
    private let logger: LoggerProtocol

    // MARK: - State

    private var _particleCount: Int = 0
    private var _isHighQuality = false
    private var _sourceImage: CGImage?

    private let stateQueue = DispatchQueue(label: "com.particleflow.coordinator.state", attributes: .concurrent)

    // MARK: - Initialization

    init(renderer: MetalRendererProtocol,
         simulationEngine: SimulationEngineProtocol,
         storage: ParticleStorageProtocol,
         configManager: ConfigurationManagerProtocol,
         memoryManager: MemoryManagerProtocol,
         generator: ParticleGeneratorProtocol,
         logger: LoggerProtocol = Logger.shared) {

        self.renderer = renderer
        self.simulationEngine = simulationEngine
        self.storage = storage
        self.configManager = configManager
        self.memoryManager = memoryManager
        self.generator = generator
        self.logger = logger

        super.init()

        setupCallbacks()
        logger.info("ParticleSystemCoordinator initialized")

        // Очищаем кэш генератора при запуске для применения обновлений
        generator.clearCache()
        logger.info("Cache cleared on startup")
    }

    // MARK: - ParticleSystemCoordinatorProtocol

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

    func updateConfiguration(_ config: ParticleGenerationConfig) async {
        logger.info("Updating configuration: \(config.qualityPreset)")
        configManager.apply(config)

        // Перегенерировать частицы с новой конфигурацией
        await regenerateParticlesIfNeeded()
    }

    func configure(screenSize: CGSize) {
        logger.info("Configuring screen size: \(screenSize)")
        // screenSize is now managed only in MetalRenderer
    }

    func replaceWithHighQualityParticles(completion: @escaping (Bool) -> Void) {
        guard let image = _sourceImage else {
            logger.error("No source image available for high-quality generation")
            completion(false)
            return
        }

        logger.info("Replacing with high-quality particles")

        Task { [weak self] in
            guard let self = self else {
                await MainActor.run { completion(false) }
                return
            }
            do {
                let config = self.configManager.currentConfig
                let particles = try await self.generator.generateParticles(from: image, config: config, screenSize: renderer.screenSize)
                self.storage.updateParticles(particles)
                self._isHighQuality = true
                self.logger.info("High-quality particles generated: \(particles.count) particles")
                self.logger.info("High-quality particles updated in storage, isHighQuality: \(self._isHighQuality)")
                await MainActor.run { completion(true) }
            } catch {
                self.logger.error("Failed to generate high-quality particles: \(error)")
                await MainActor.run { completion(false) }
            }
        }
    }

    func initializeFastPreview() {
        logger.info("Initializing fast preview")
        storage.createFastPreviewParticles()
        _isHighQuality = false
        startSimulation()
    }

    func cleanup() {
        logger.info("Cleaning up particle system")

        stopSimulation()
        renderer.cleanup()
        storage.clear()
        memoryManager.releaseMemory()

        _particleCount = 0
        _isHighQuality = false
        _sourceImage = nil
    }

    var hasActiveSimulation: Bool {
        simulationEngine.isActive
    }

    var isHighQuality: Bool {
        stateQueue.sync { _isHighQuality }
    }

    var particleCount: Int {
        stateQueue.sync { _particleCount }
    }

    var sourceImage: CGImage? {
        stateQueue.sync { _sourceImage }
    }

    var particleBuffer: MTLBuffer? {
        storage.particleBuffer
    }

    // MARK: - Public Methods

    /// Инициализирует систему с изображением
    func initialize(with image: CGImage, particleCount: Int, config: ParticleGenerationConfig) {
        logger.info("Initializing with image: \(image.width)x\(image.height), particles: \(particleCount)")

        stateQueue.async(flags: .barrier) { [weak self] in
            self?._sourceImage = image
            self?._particleCount = particleCount
        }

        // Initialize storage with particle count
        storage.initialize(with: particleCount)

        configManager.apply(config)
    }

    // MARK: - Private Methods

    private func setupCallbacks() {
        // Настройка колбеков между компонентами
        simulationEngine.resetCounterCallback = { [weak self] in
            self?.renderer.resetCollectedCounter()
        }
    }

    private func regenerateParticlesIfNeeded() async {
        // Логика для определения необходимости перегенерации
        // Пока что перегенерируем всегда при изменении конфигурации
        if let image = _sourceImage {
            do {
                let config = configManager.currentConfig
                _ = try await generator.generateParticles(from: image, config: config, screenSize: renderer.screenSize)
                logger.debug("Particles regenerated with new configuration")
            } catch {
                logger.error("Failed to regenerate particles: \(error)")
            }
        }
    }

    // MARK: - Render Loop Integration

    /// Вызывается в render loop для обновления симуляции
    func updateSimulation(deltaTime: Float) {
        logger.debug("Coordinator.updateSimulation() deltaTime=\(deltaTime)")

        simulationEngine.update(deltaTime: deltaTime)
        renderer.updateSimulationParams()
    }

    /// Вызывается в render loop для проверки завершения сбора
    func checkCollectionCompletion() {
        renderer.checkCollectionCompletion()
    }
}

// MARK: - Factory

enum ParticleSystemFactory {
    static func makeCoordinator() -> ParticleSystemCoordinator {
        // Получить зависимости из DI контейнера
        guard let metalRenderer = resolve(MetalRendererProtocol.self),
              let simulationEngine = resolve(SimulationEngineProtocol.self),
              let storage = resolve(ParticleStorageProtocol.self),
              let configManager = resolve(ConfigurationManagerProtocol.self),
              let memoryManager = resolve(MemoryManagerProtocol.self),
              let generator = resolve(ParticleGeneratorProtocol.self),
              let logger = resolve(LoggerProtocol.self) else {
            fatalError("Failed to resolve ParticleSystem dependencies")
        }

        return ParticleSystemCoordinator(
            renderer: metalRenderer,
            simulationEngine: simulationEngine,
            storage: storage,
            configManager: configManager,
            memoryManager: memoryManager,
            generator: generator,
            logger: logger
        )
    }
}
