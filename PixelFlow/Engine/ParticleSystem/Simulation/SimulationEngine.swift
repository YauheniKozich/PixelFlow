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
final class SimulationEngine: SimulationEngineProtocol, PhysicsEngineProtocol {

    // MARK: - Properties

    private let stateMachine: StateManagerProtocol
    let clock: SimulationClockProtocol
    private let logger: LoggerProtocol
    private let particleStorage: ParticleStorageProtocol

    var state: SimulationState { stateMachine.currentState }
    var resetCounterCallback: (() -> Void)?

    // MARK: - Initialization

    init(stateManager: StateManagerProtocol,
         clock: SimulationClockProtocol,
         logger: LoggerProtocol,
         particleStorage: ParticleStorageProtocol) {

        self.stateMachine = stateManager
        self.clock = clock
        self.logger = logger
        self.particleStorage = particleStorage

        logger.info("SimulationEngine initialized")
    }

    // MARK: - SimulationEngineProtocol

    var isActive: Bool {
        stateMachine.isActive
    }

    func start() {
        logger.info("Starting simulation")
        
        // Создаем fast preview частицы с начальными скоростями
        particleStorage.createFastPreviewParticles()
        
        stateMachine.transition(to: .chaotic)
        resetCounterCallback?()
    }

    func stop() {
        logger.info("Stopping simulation")
        stateMachine.transition(to: .idle)
    }

    func startCollecting() {
        logger.info("Starting particle collection")
        startCollectionTracking()
        
        // КРИТИЧНО: Создаем целевые high-quality частицы перед началом сборки
        particleStorage.recreateHighQualityParticles()
        
        stateMachine.transition(to: .collecting(progress: 0.0))
        resetCounterCallback?()
    }

    func startLightningStorm() {
        logger.info("Starting lightning storm")
        stateMachine.transition(to: .lightningStorm)
    }

    func updateProgress(_ progress: Float) {
        guard case .collecting = stateMachine.currentState else { return }

        logger.debug("updateProgress called with progress: \(String(format: "%.3f", progress))")

        // Проверяем условия завершения сбора
        if shouldCompleteCollection(progress: progress) {
            logger.info("Collection completed with progress: \(String(format: "%.3f", progress))")
            stateMachine.transition(to: .collected(frames: 0))
        } else {
            stateMachine.transition(to: .collecting(progress: progress))
        }
    }

    func update(deltaTime: Float) {
        clock.update(with: deltaTime)
        
        logger.debug("SimulationEngine.update() deltaTime=\(deltaTime) state=\(stateMachine.currentState)")

        // Применяем силы (если нужно)
        applyForces()

        // Обновляем частицы в зависимости от текущего состояния
        switch stateMachine.currentState {
        case .idle:
            // В idle ничего не делаем
            break
            
        case .chaotic:
            // В хаотичном режиме частицы двигаются по своим velocity
            logger.debug("Updating chaotic particles")
            particleStorage.updateFastPreview(deltaTime: deltaTime)
            
        case .collecting:
            // В режиме сборки частицы плавно перемещаются к целевым позициям
            logger.debug("Updating collecting particles")
            particleStorage.updateHighQualityTransition(deltaTime: deltaTime)
            
        case .collected:
            // В собранном состоянии частицы статичны
            break
            
        case .lightningStorm:
            // В режиме молний можно добавить специальную логику
            logger.debug("Updating lightning storm particles")
            particleStorage.updateFastPreview(deltaTime: deltaTime)
        }
    }

    func applyForces() {
        // Здесь можно добавить дополнительные физические силы:
        // - Гравитацию
        // - Отталкивание от краев экрана
        // - Турбулентность
        // - Притяжение к центру в режиме collecting
        // Пока оставляем пустым - логика в ParticleStorage
    }

    func reset() {
        clock.reset()
        stateMachine.transition(to: .idle)
        particleStorage.clear()
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

    // MARK: - Private Methods

    private func shouldCompleteCollection(progress: Float) -> Bool {
        let currentTime = ProcessInfo.processInfo.systemUptime

        // 1. Порог готовности достигнут (99%)
        if progress >= 0.99 {
            logger.info("Collection complete: progress threshold reached (\(String(format: "%.3f", progress)))")
            return true
        }

        // 2. Общий таймаут (30 секунд)
        if currentTime - collectionStartTime > 30.0 {
            logger.warning("Collection complete: timeout reached (30s)")
            return true
        }

        // 3. Застрявший прогресс (5 секунд без улучшения)
        if progress > 0 && progress == lastProgress &&
           currentTime - lastProgressUpdateTime > 5.0 {
            logger.warning("Collection complete: progress stalled at \(String(format: "%.3f", progress))")
            return true
        }

        // Обновляем время последнего прогресса только если он действительно изменился
        if progress != lastProgress {
            lastProgressUpdateTime = currentTime
            lastProgress = progress
        }

        return false
    }

    // MARK: - Collection State Tracking

    private var collectionStartTime: TimeInterval = 0
    private var lastProgressUpdateTime: TimeInterval = 0
    private var lastProgress: Float = 0

    private func startCollectionTracking() {
        let currentTime = ProcessInfo.processInfo.systemUptime
        collectionStartTime = currentTime
        lastProgressUpdateTime = currentTime
        lastProgress = 0
        
        logger.debug("Collection tracking started at \(currentTime)")
    }
}

// MARK: - Default Implementations

final class DefaultSimulationClock: SimulationClockProtocol {
    private(set) var time: Float = 0
    private(set) var deltaTime: Float = ParticleConstants.defaultDeltaTime
    private var lastTimestamp: CFTimeInterval = 0

    func update() {
        let now = CACurrentMediaTime()
        let dt = lastTimestamp > 0 ? Float(now - lastTimestamp) : deltaTime
        lastTimestamp = now

        deltaTime = min(max(dt, 1e-4), 0.1)
        time += deltaTime
    }

    func update(with deltaTime: Float) {
        self.deltaTime = min(max(deltaTime, 1e-4), 0.1)
        time += self.deltaTime
    }

    func reset() {
        time = 0
        deltaTime = ParticleConstants.defaultDeltaTime
        lastTimestamp = 0
    }
}

final class DefaultStateManager: StateManagerProtocol {
    private(set) var currentState: SimulationState = .idle

    var isActive: Bool {
        if case .idle = currentState { return false }
        return true
    }

    func transition(to state: SimulationState) {
        currentState = state
    }
}
