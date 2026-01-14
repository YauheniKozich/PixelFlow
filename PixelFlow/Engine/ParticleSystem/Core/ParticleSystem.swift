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
    var screenSize: CGSize = .zero
    var isConfigured = false
    private(set) var isUsingFastPreview: Bool = false
    
    var renderPipeline: MTLRenderPipelineState!
    var computePipeline: MTLComputePipelineState!
    
    var particleBuffer: MTLBuffer!
    var paramsBuffer: MTLBuffer!
    var collectedCounterBuffer: MTLBuffer!
    
    let stateMachine = SimulationStateMachine()
    let clock = SimulationClock()
    let paramsUpdater = SimulationParamsUpdater()
    let particleGenerator: ParticleGenerator

    /// Текущая конфигурация системы частиц
    private(set) var currentConfig: ParticleGenerationConfig
    
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
    
    func configure(screenSize: CGSize) {
        precondition(!isConfigured, "ParticleSystem уже сконфигурирован")
        self.screenSize = screenSize
        imageController.updateScreenSize(screenSize)
        particleGenerator.updateScreenSize(screenSize)
        isConfigured = true
    }
    
    /// Основная инициализация с качественными частицами
    func initialize() {
        precondition(isConfigured, "Вызовите configure(screenSize:) перед initialize()")
        isUsingFastPreview = false
        particleGenerator.recreateParticles(in: particleBuffer)
    }
    
    /// Быстрая инициализация с low-quality превью
    func initializeWithFastPreview() {
        precondition(isConfigured, "Вызовите configure(screenSize:) перед initialize()")
        isUsingFastPreview = true
        particleGenerator.createAndCopyFastPreviewParticles(in: particleBuffer)
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
                self.particleGenerator.recreateParticles(in: self.particleBuffer)
                self.isUsingFastPreview = false
                DispatchQueue.main.async { completion(true) }
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

        let imageController: ImageParticleGeneratorProtocol

        do {
            imageController = try ImageParticleGenerator(image: image, particleCount: particleCount, config: config)
        } catch {
            return nil
        }
        
        self.imageController = imageController
        self.particleGenerator = ParticleGenerator(
            particleSystem: nil,
            imageController: imageController,
            particleCount: particleCount
        )

        super.init()
        particleGenerator.weakParticleSystem = self
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
        particleGenerator.cleanup()
        imageController.clearCache()
        isUsingFastPreview = false
    }
    
    func stop() {
        stateMachine.stop()
    }
}
