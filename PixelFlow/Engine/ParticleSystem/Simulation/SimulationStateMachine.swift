//
//  SimulationStateMachine.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation

// MARK: - SimulationState

/// Состояние симуляции частиц
enum SimulationState: Equatable {
    case idle
    case chaotic
    case collecting(progress: Float)
    case collected(frames: Int)
    case lightningStorm
}

final class SimulationStateMachine {
    enum CollectMode {
        case toImage
        case toScatter
    }

    private(set) var state: SimulationState = .idle
    var resetCounterCallback: (() -> Void)?
    private var collectMode: CollectMode = .toImage

    // Таймаут для сбора частиц
    private var collectionElapsedTime: TimeInterval = 0

    // Константы таймаута
    private let maxCollectionTime: TimeInterval = 30.0  // 30 секунд максимум
    
    var isActive: Bool {
        if case .idle = state { return false }
        return true
    }
    
    func start() {
        Logger.shared.info("[StateMachine] start() → .chaotic")
        
        // Сбрасываем счетчик собранных частиц при начале новой симуляции
        resetCounterCallback?()
        
        state = .chaotic
    }
    
    func startCollecting(mode: CollectMode = .toImage) {
        Logger.shared.info("[StateMachine] startCollecting() → .collecting(0)")

        // Сбрасываем счетчик собранных частиц
        resetCounterCallback?()

        // Инициализируем таймаут сбора
        collectionElapsedTime = 0
        collectMode = mode

        state = .collecting(progress: 0)
    }
    
    func updateProgress(_ progress: Float) {
        guard case .collecting = state else { return }

        let clampedProgress = min(max(progress, 0), 1)

        // Проверяем условия завершения сбора
        if clampedProgress >= 1.0 {
            Logger.shared.info("[StateMachine] Collection complete → .collected(0) [progress >= 100%]")
            switch collectMode {
            case .toImage:
                state = .collected(frames: 0)
            case .toScatter:
                state = .chaotic
            }
            return
        }

        if collectionElapsedTime > maxCollectionTime {
            Logger.shared.warning(
                "[StateMachine] Collection timed out at \(Int(clampedProgress * 100))%; returning to chaotic state"
            )
            state = .chaotic
            return
        }

        state = .collecting(progress: clampedProgress)
    }
    
    func advanceCollectionTime(by deltaTime: Float) {
        guard case .collecting = state, deltaTime.isFinite, deltaTime > 0 else { return }
        collectionElapsedTime += TimeInterval(deltaTime)
    }

    func tickCollected() {
        guard case .collected(let frames) = state else { return }
        let newFrames = frames + 1
        state = .collected(frames: newFrames)
    }
    
    func stop() {
        Logger.shared.info("[StateMachine] stop() → .idle")
        state = .idle
    }
    
    func startLightningStorm() {
        Logger.shared.info("[StateMachine] startLightningStorm() → .lightningStorm")
        state = .lightningStorm
    }
}
