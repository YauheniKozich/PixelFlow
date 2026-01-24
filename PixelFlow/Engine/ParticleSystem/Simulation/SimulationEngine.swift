//
//  SimulationEngine.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Движок симуляции частиц
//

import Foundation
import QuartzCore

/// Движок симуляции частиц
final class SimulationEngine {
    
    // MARK: - Properties
    private let stateMachine: SimulationStateMachine
    internal let clock: SimulationClockProtocol
    private let logger: LoggerProtocol
    private let particleStorage: ParticleStorageProtocol
    
    var state: SimulationState { stateMachine.state }
    var resetCounterCallback: (() -> Void)?
    var customForces: ((Float) -> Void)?
    
    private var hqParticlesReady = false
    
    // MARK: - Initialization
    init(stateManager: SimulationStateMachine,
         clock: SimulationClockProtocol,
         logger: LoggerProtocol,
         particleStorage: ParticleStorageProtocol) {
        
        self.stateMachine = stateManager
        self.clock = clock
        self.logger = logger
        self.particleStorage = particleStorage
        
        logger.info("SimulationEngine initialized")
    }
    
    // MARK: - Private Methods
    /// Обрабатывает обновление частиц в зависимости от текущего состояния симуляции
    @MainActor private func handleStateUpdate(deltaTime: Float) {
        switch stateMachine.state {
        case .idle:
            break
            
        case .chaotic:
            particleStorage.updateFastPreview(deltaTime: deltaTime)
            
        case .collecting:
            guard hqParticlesReady else {
                logger.warning("Cannot update collecting particles - HQ particles not ready")
                return
            }
            logger.debug("Updating collecting particles")
            particleStorage.updateHighQualityTransition(deltaTime: deltaTime)
            let progress = particleStorage.getTransitionProgress()
            updateProgress(progress)
            
        case .collected:
            break
            
        case .lightningStorm:
            particleStorage.updateFastPreview(deltaTime: deltaTime)
        }
    }
    
    /// Применяет физические силы к частицам
    internal func applyForces() {
        customForces?(clock.deltaTime)
    }
}

// MARK: - SimulationEngineProtocol
extension SimulationEngine: SimulationEngineProtocol {
    
    var isActive: Bool {
        stateMachine.isActive
    }
    
    /// Запускает симуляцию в хаотичном режиме
    func start() {
        logger.info("Starting simulation")
        
        // Создаем fast preview частицы с начальными скоростями
        particleStorage.createFastPreviewParticles()
        
        // Генерируем HQ частицы асинхронно
        particleStorage.generateHighQualityParticles { [weak self] in
            guard let self = self else { return }
            self.hqParticlesReady = true
            self.stateMachine.start()
            self.resetCounterCallback?()
            self.logger.info("Simulation started with HQ particles ready")
        }
    }
    
    /// Останавливает симуляцию
    func stop() {
        logger.info("Stopping simulation")
        stateMachine.stop()
    }
    
    /// Запускает режим сбора частиц
    func startCollecting() {
        logger.info("Starting particle scattering (breaking apart)")
        guard hqParticlesReady else {
            logger.warning("Cannot start collecting - HQ particles not ready")
            return
        }
        
        particleStorage.createScatteredTargets()
        stateMachine.startCollecting()
        resetCounterCallback?()
    }
    
    /// Запускает режим молний
    func startLightningStorm() {
        logger.info("Starting lightning storm")
        stateMachine.startLightningStorm()
    }
    
    func updateProgress(_ progress: Float) {
        guard case .collecting = stateMachine.state else { return }
        logger.debug("updateProgress called with progress: \(String(format: "%.3f", progress))")
        stateMachine.updateProgress(progress)
    }
    
    /// Обновляет состояние симуляции на основе прошедшего времени
    func update(deltaTime: Float) {
        let clampedDeltaTime = min(deltaTime, 0.1)
        clock.update(with: clampedDeltaTime)
        applyForces()
        handleStateUpdate(deltaTime: clampedDeltaTime)
    }
    
    /// Применяет физические силы к частицам
    func applyForcesExternally() {
        applyForces()
    }
    
    func reset() {
        logger.info("Resetting simulation engine")
        clock.reset()
        stateMachine.stop()
        particleStorage.clear()
        hqParticlesReady = false
    }
    
    // MARK: - Public Methods
    func updateClock() {
        clock.update()
    }
    
    func getCurrentTime() -> Float {
        clock.time
    }
    
    func getDeltaTime() -> Float {
        clock.deltaTime
    }
}
