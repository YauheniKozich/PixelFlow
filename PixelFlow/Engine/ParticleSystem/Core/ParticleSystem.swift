//
//  ParticleSystem.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit


// MARK: - Файл ParticleSystem.swift (основной координатор)


// MARK: - Particle System

final class ParticleSystem: NSObject {
    
    // MARK: Idle Chaotic Motion
    /// Enables chaotic motion in idle state
    var enableIdleChaotic: Bool = false
    
    // MARK: MTKView Reference (for screen scale)
    private weak var mtkView: MTKView?
    
    // MARK: Dependencies
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let imageController: ImageParticleGeneratorProtocol
    
    // MARK: Configuration
    let particleCount: Int
    var screenSize: CGSize = .zero
    var isConfigured = false
    
    // MARK: Metal
    var renderPipeline: MTLRenderPipelineState!
    var computePipeline: MTLComputePipelineState!
    
    var particleBuffer: MTLBuffer!
    var paramsBuffer: MTLBuffer!
    var collectedCounterBuffer: MTLBuffer!
    
    // MARK: Subsystems
    let stateMachine = SimulationStateMachine()
    let clock = SimulationClock()
    let paramsUpdater = SimulationParamsUpdater()
    let particleGenerator: ParticleGenerator
    
    var lastProgressLogTime: CFTimeInterval = 0
    var lastLoggedCollectedCount: Int = -1
    
    // MARK: Public API
    var hasActiveSimulation: Bool {
        stateMachine.isActive
    }
    
    func startSimulation() {
        Logger.shared.info("startSimulation() called")
        stateMachine.start()
    }
    
    func toggleState() {
        let currentState = stateMachine.state
        Logger.shared.info("toggleState() called, current state: \(currentState)")
        
        switch stateMachine.state {
        case .chaotic:
            Logger.shared.info("→ Transitioning to .collecting")
            stateMachine.startCollecting()
        case .collecting:
            Logger.shared.info("→ Back to chaotic (not stopping)")
            stateMachine.start()  // Вернуться к хаосу, не останавливать
        case .collected:
            Logger.shared.info("→ Restarting from collected")
            stateMachine.start()  // Перезапуск из собранного состояния
        case .idle:
            Logger.shared.info("→ Starting from idle")
            stateMachine.start()
        case .lightningStorm:
            Logger.shared.info("→ Exiting storm to chaotic")
            stateMachine.start()
        }
    }
    
    func startLightningStorm() {
        stateMachine.startLightningStorm()
    }
    
    func configure(screenSize: CGSize) {
        precondition(!isConfigured, "ParticleSystem already configured")
        self.screenSize = screenSize
        imageController.updateScreenSize(screenSize)
        particleGenerator.updateScreenSize(screenSize)
        isConfigured = true
    }
    
    func initialize() {
        precondition(isConfigured, "Call configure(screenSize:) before initialize()")
        particleGenerator.recreateParticles(in: particleBuffer)
    }

    /// Быстрая инициализация с простыми частицами (не блокирует UI)
    func initializeWithSimpleParticles() {
        precondition(isConfigured, "Call configure(screenSize:) before initialize()")
        particleGenerator.createAndCopySimpleParticles(in: particleBuffer)
    }

    /// Асинхронная замена частиц на сгенерированные из изображения
    func replaceParticlesAsync(completion: @escaping (Bool) -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else {
                DispatchQueue.main.async { completion(false) }
                return
            }

            do {
                Logger.shared.info("Starting async particle generation...")
                try self.particleGenerator.recreateParticles(in: self.particleBuffer)
                Logger.shared.info("Particles replaced successfully")
                DispatchQueue.main.async { completion(true) }
            } catch {
                Logger.shared.error("Failed to replace particles: \(error)")
                DispatchQueue.main.async { completion(false) }
            }
        }
    }
    
    // MARK: Init
    init?(mtkView: MTKView, image: CGImage, particleCount: Int, config: ParticleGenerationConfig? = nil) {
        Logger.shared.info("ParticleSystem init started")
        // Сначала инициализируем все свойства
        guard
            let device = MTLCreateSystemDefaultDevice(),
            let queue = device.makeCommandQueue()
        else {
            Logger.shared.error("Failed to create Metal device/queue")
            return nil
        }

        guard particleCount > 0 else {
            Logger.shared.error("Invalid particle count: \(particleCount)")
            return nil
        }
        
        self.device = device
        self.commandQueue = queue
        self.particleCount = particleCount
        
        // Инициализируем imageController до вызова super.init()
        Logger.shared.info("Creating ImageParticleGeneratorProtocol...")
        let imageController: ImageParticleGeneratorProtocol

        do {
            if let config = config {
                imageController = try ImageParticleGenerator(image: image, particleCount: particleCount, config: config)
            } else {
                imageController = try ImageParticleGenerator(image: image, particleCount: particleCount)
            }
            Logger.shared.info("ImageParticleGenerator created successfully")
        } catch {
            Logger.shared.error("Failed to create ImageParticleGenerator: \(error)")
            return nil
        }
        self.imageController = imageController

        // Инициализируем particleGenerator до super.init()
        self.particleGenerator = ParticleGenerator(
                    particleSystem: nil,  // Пока nil, установим после super.init()
                    imageController: imageController,
                    particleCount: particleCount
                )

        // Теперь вызываем super.init()
        super.init()

        // После super.init() можем использовать self
        particleGenerator.weakParticleSystem = self
        
        
        // После super.init() можем использовать self
        self.mtkView = mtkView
        self.stateMachine.resetCounterCallback = { [weak self] in
            self?.resetCollectedCounterIfNeeded()
        }
        
        configureView(mtkView)
        validateStructLayouts()
        
        do {
            try setupPipelines(view: mtkView)
            try setupBuffers()
        } catch {
            return nil
        }
    }
    
    var mtkViewForGenerator: MTKView? {
            return mtkView
        }
}

