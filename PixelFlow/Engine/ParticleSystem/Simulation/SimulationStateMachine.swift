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
    
    func startCollecting(mode: CollectMode = .toImage) {
        Logger.shared.info("[StateMachine] startCollecting() → .collecting(0)")

        // Сбрасываем счетчик собранных частиц
        resetCounterCallback?()

        // Инициализируем таймаут сбора
        let currentTime = ProcessInfo.processInfo.systemUptime
        collectionStartTime = currentTime
        lastProgressUpdateTime = currentTime
        lastProgress = 0
        collectMode = mode

        state = .collecting(progress: 0)
    }
    
    func updateProgress(_ progress: Float) {
        guard case .collecting = state else { return }

        let clampedProgress = min(max(progress, 0), 1)
        let currentTime = ProcessInfo.processInfo.systemUptime

        // Проверяем условия завершения сбора
        var shouldComplete = false
        var reason = ""

        // 1. Полная готовность (100%)
        if clampedProgress >= 1.0 {
            shouldComplete = true
            reason = "progress >= 100%"
        }
        // 2. Общий таймаут (30 секунд)
        else if currentTime - collectionStartTime > maxCollectionTime {
            shouldComplete = true
            reason = "timeout (\(String(format: "%.1f", maxCollectionTime))s)"
        }

        if shouldComplete {
            lastProgress = 1.0
            Logger.shared.info("[StateMachine] Collection complete → .collected(0) [\(reason)]")
            switch collectMode {
            case .toImage:
                state = .collected(frames: 0)
            case .toScatter:
                state = .chaotic
            }
        } else {
            // Обновляем время последнего прогресса только если он действительно изменился
            let epsilon: Float = 1e-6
            if abs(clampedProgress - lastProgress) > epsilon {
                lastProgressUpdateTime = currentTime
                lastProgress = clampedProgress
            }
            state = .collecting(progress: clampedProgress)
        }
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
