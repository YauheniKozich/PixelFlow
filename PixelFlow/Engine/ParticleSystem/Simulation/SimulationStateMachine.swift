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

    private(set) var state: SimulationState = .idle
    var resetCounterCallback: (() -> Void)?

    // Таймаут для сбора частиц
    private var collectionStartTime: TimeInterval = 0
    private var lastProgressUpdateTime: TimeInterval = 0
    private var lastProgress: Float = 0

    // Константы таймаута
    private let maxCollectionTime: TimeInterval = 30.0  // 30 секунд максимум
    private let progressStagnationTimeout: TimeInterval = 5.0  // 5 секунд без прогресса
    
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
    
    func startCollecting() {
        Logger.shared.info("[StateMachine] startCollecting() → .collecting(0)")

        // Сбрасываем счетчик собранных частиц
        resetCounterCallback?()

        // Инициализируем таймаут сбора
        let currentTime = ProcessInfo.processInfo.systemUptime
        collectionStartTime = currentTime
        lastProgressUpdateTime = currentTime
        lastProgress = 0

        state = .collecting(progress: 0)
    }
    
    func updateProgress(_ progress: Float) {
        guard case .collecting = state else { return }

        Logger.shared.debug("[StateMachine] updateProgress(\(String(format: "%.3f", progress))) called on thread: \(Thread.isMainThread ? "MAIN" : "BACKGROUND") at \(Date().timeIntervalSince1970)")

        let currentTime = ProcessInfo.processInfo.systemUptime

        // Проверяем условия завершения сбора
        var shouldComplete = false
        var reason = ""

        // 1. Порог готовности достигнут
        if progress >= 0.99 {
            shouldComplete = true
            reason = "progress >= 99%"
        }
        // 2. Общий таймаут (30 секунд)
        else if currentTime - collectionStartTime > maxCollectionTime {
            shouldComplete = true
            reason = "timeout (\(String(format: "%.1f", maxCollectionTime))s)"
        }
        // 3. Застрявший прогресс (5 секунд без улучшения)
        else if progress > 0 && progress == lastProgress &&
                  currentTime - lastProgressUpdateTime > progressStagnationTimeout {
            shouldComplete = true
            reason = "stagnation (\(String(format: "%.1f", progressStagnationTimeout))s no progress)"
        }

        if shouldComplete {
            Logger.shared.info("[StateMachine] updateProgress(\(String(format: "%.3f", progress))) → .collected(0) [\(reason)]")
            state = .collected(frames: 0)
        } else {
            // Обновляем время последнего прогресса только если он действительно изменился
            let epsilon: Float = 1e-6
            if abs(progress - lastProgress) > epsilon {
                lastProgressUpdateTime = currentTime
                lastProgress = progress
            }
            state = .collecting(progress: progress)
        }
    }
    
    func tickCollected() {
        guard case .collected(let frames) = state else { return }
        let newFrames = frames + 1
        state = .collected(frames: newFrames)
        Logger.shared.debug("[StateMachine] tickCollected() → frames=\(newFrames)")
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
