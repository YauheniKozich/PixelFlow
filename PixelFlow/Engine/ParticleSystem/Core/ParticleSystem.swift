//
//  ParticleSystem.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit

final class ParticleSystem: NSObject {
    
    // MARK: - Свойства
    
    var enableIdleChaotic: Bool = false
    private weak var mtkView: MTKView?
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let imageController: ImageParticleGeneratorProtocol
    
    let particleCount: Int
    var isConfigured = false
    private(set) var isUsingFastPreview: Bool = false
    
    var renderPipeline: MTLRenderPipelineState!
    var computePipeline: MTLComputePipelineState!
    
    var particleBuffer: MTLBuffer!
    var paramsBuffer: MTLBuffer!
    var collectedCounterBuffer: MTLBuffer!
    
    let stateMachine = SimulationStateMachine()
    let simulationClock = SimulationClock()
    let paramsUpdater = SimulationParamsUpdater()
    let particleGenerator: ParticleGenerator
    let renderer: MetalRenderer

    /// Текущая конфигурация системы частиц
    private(set) var currentConfig: ParticleGenerationConfig

    // MARK: - SimulationEngineProtocol conformance

    var state: SimulationState {
        return stateMachine.state
    }

    var isActive: Bool {
        return stateMachine.isActive
    }

    var resetCounterCallback: (() -> Void)? {
        get { return stateMachine.resetCounterCallback }
        set { stateMachine.resetCounterCallback = newValue }
    }

    var clock: SimulationClockProtocol {
        return simulationClock
    }

    // MARK: - Публичный интерфейс
    
    var hasActiveSimulation: Bool {
        stateMachine.isActive
    }
    
    var isHighQuality: Bool {
        !isUsingFastPreview
    }
    
    func startSimulation() {
        stateMachine.start()
    }
    
    func toggleState() {
        switch stateMachine.state {
        case .chaotic:
            stateMachine.startCollecting()
        case .collecting:
            stateMachine.start()
        case .collected:
            stateMachine.start()
        case .idle:
            stateMachine.start()
        case .lightningStorm:
            stateMachine.start()
        }
    }
    
    func startLightningStorm() {
        stateMachine.startLightningStorm()
    }
    

    
    /// Основная инициализация с качественными частицами
    func initialize() {
        precondition(isConfigured, "Вызовите configure(screenSize:) перед initialize()")
        Logger.shared.info("Initializing high-quality particles")
        isUsingFastPreview = false
        particleGenerator.recreateParticles(in: particleBuffer, screenSize: renderer.screenSize)
        Logger.shared.info("High-quality particles initialized")
    }
    
    /// Быстрая инициализация с low-quality превью
    func initializeWithFastPreview() {
        precondition(isConfigured, "Вызовите configure(screenSize:) перед initialize()")
        Logger.shared.info("Initializing fast preview particles")
        isUsingFastPreview = true
        particleGenerator.createAndCopyFastPreviewParticles(in: particleBuffer, screenSize: renderer.screenSize)
        Logger.shared.info("Fast preview particles initialized, starting simulation")
        startSimulation()
    }
    
    /// Асинхронная замена частиц на качественные
    func replaceWithHighQualityParticles(completion: @escaping (Bool) -> Void) {
        precondition(isConfigured, "Система не сконфигурирована")
        
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            do {
                // Перезаписываем существующий буфер high-quality частицами
                self.particleGenerator.recreateParticles(in: self.particleBuffer, screenSize: self.renderer.screenSize)
                self.isUsingFastPreview = false
                DispatchQueue.main.async { [weak self] in
                    // Гарантируем, что MetalRenderer использует обновлённый буфер
                    self?.renderer.setParticleBuffer(self?.particleBuffer)
                    self?.renderer.setCollectedCounterBuffer(self?.collectedCounterBuffer)
                    // Обновляем particleCount в MetalRenderer
                    self?.renderer.updateParticleCount(self?.particleCount ?? 0)
                    // После генерации high-quality частиц начинаем сбор
                    self?.stateMachine.startCollecting()
                    completion(true)
                }
            } 
        }
    }
    
    // MARK: - Инициализация
    
    init?(mtkView: MTKView, image: CGImage, particleCount: Int, config: ParticleGenerationConfig) {
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue(),
            particleCount > 0
        else {
            return nil
        }

        self.device = device
        self.commandQueue = queue
        self.particleCount = particleCount
        self.currentConfig = config
        self.renderer = MetalRenderer(device: device)

        let imageController: ImageParticleGeneratorProtocol

        do {
            imageController = try ImageParticleGenerator(image: image, particleCount: particleCount, config: config)
        } catch {
            return nil
        }
        
        self.imageController = imageController
        self.particleGenerator = ParticleGenerator(
            imageController: imageController,
            particleCount: particleCount
        )

        super.init()
        self.renderer.setSimulationEngine(self)
        self.mtkView = mtkView
        self.stateMachine.resetCounterCallback = { [weak self] in
            self?.resetCollectedCounterIfNeeded()
        }
        
        configureView(mtkView)
        validateStructLayouts()
        
        do {
            try setupPipelines(view: mtkView)
            try setupBuffers()
            renderer.setParticleBuffer(particleBuffer)
            renderer.setCollectedCounterBuffer(collectedCounterBuffer)
            renderer.updateParticleCount(particleCount)
        } catch {
            return nil
        }
    }
    
    var mtkViewForGenerator: MTKView? {
        return mtkView
    }
    
    func getSourceImage() -> CGImage? {
        return imageController.image
    }
    
    func cleanup() {
        stateMachine.stop()
        particleBuffer = nil
        paramsBuffer = nil
        collectedCounterBuffer = nil
        renderPipeline = nil
        computePipeline = nil
        renderer.cleanup()
        particleGenerator.cleanup()
        imageController.clearCache()
        isUsingFastPreview = false
    }
    
    func stop() {
        stateMachine.stop()
    }
}

// MARK: - SimulationEngineProtocol
extension ParticleSystem: SimulationEngineProtocol {
    func start() {
        startSimulation()
    }

    func startCollecting() {
        stateMachine.startCollecting()
    }

    func updateProgress(_ progress: Float) {
        stateMachine.updateProgress(progress)
    }
}
