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

    private(set) var state: SimulationState = .idle
    var resetCounterCallback: (() -> Void)?

    private let stateMachine: ParticleSystemStateManagerProtocol
    private let clock: SimulationClockProtocol
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(stateManager: ParticleSystemStateManagerProtocol = DefaultStateManager(),
         clock: SimulationClockProtocol = DefaultSimulationClock(),
         logger: LoggerProtocol = Logger.shared) {

        self.stateMachine = stateManager
        self.clock = clock
        self.logger = logger

        logger.info("SimulationEngine initialized")
    }

    // MARK: - SimulationEngineProtocol

    var isActive: Bool {
        stateMachine.isActive
    }

    func start() {
        logger.info("Starting simulation")
        stateMachine.transition(to: .chaotic)
        resetCounterCallback?()
    }

    func stop() {
        logger.info("Stopping simulation")
        stateMachine.transition(to: .idle)
    }

    func startCollecting() {
        logger.info("Starting particle collection")
        stateMachine.transition(to: .collecting(progress: 0.0))
        resetCounterCallback?()
    }

    func startLightningStorm() {
        logger.info("Starting lightning storm")
        stateMachine.transition(to: .lightningStorm)
    }

    func updateProgress(_ progress: Float) {
        guard case .collecting = stateMachine.currentState else { return }

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
        // Здесь будет логика обновления физики частиц
    }

    func applyForces() {
        // Здесь будет логика применения сил
    }

    func reset() {
        clock.reset()
        stateMachine.transition(to: .idle)
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

        // 1. Порог готовности достигнут
        if progress >= 0.99 {
            return true
        }

        // 2. Общий таймаут (30 секунд)
        if currentTime - collectionStartTime > 30.0 {
            return true
        }

        // 3. Застрявший прогресс (5 секунд без улучшения)
        if progress > 0 && progress == lastProgress &&
           currentTime - lastProgressUpdateTime > 5.0 {
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
    }
}

// MARK: - Supporting Protocols and Classes

protocol SimulationClockProtocol {
    var time: Float { get }
    var deltaTime: Float { get }

    func update()
    func update(with deltaTime: Float)
    func reset()
}

protocol ParticleSystemStateManagerProtocol {
    var currentState: SimulationState { get }

    func transition(to state: SimulationState)
    var isActive: Bool { get }
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

final class DefaultStateManager: ParticleSystemStateManagerProtocol {
    private(set) var currentState: SimulationState = .idle

    var isActive: Bool {
        if case .idle = currentState { return false }
        return true
    }

    func transition(to state: SimulationState) {
        currentState = state
    }
}

// MARK: - SimulationState

enum SimulationState {
    case idle
    case chaotic
    case collecting(progress: Float)
    case collected(frames: Int)
    case lightningStorm
}