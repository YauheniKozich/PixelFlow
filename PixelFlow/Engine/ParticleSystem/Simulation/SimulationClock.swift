//
//  SimulationClock.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Класс для управления временем симуляции
//

import Foundation

/// Протокол для управления временем симуляции
protocol SimulationClockProtocol {
    var time: Float { get }
    var deltaTime: Float { get }
    
    func start()
    func stop()
    func update(with deltaTime: Float)
    func reset()
}

/// Дефолтная реализация SimulationClockProtocol с использованием CACurrentMediaTime
final class DefaultSimulationClock: SimulationClockProtocol {
    private static let defaultDeltaTime: Float = 1.0 / 60.0

    private(set) var time: Float = 0
    private(set) var deltaTime: Float = defaultDeltaTime

    func start() {
        // No-op: time is driven externally via update(with:)
    }

    func stop() {
        // No-op: time is driven externally via update(with:)
    }

    func update(with deltaTime: Float) {
        self.deltaTime = min(max(deltaTime, 1e-4), 0.1)
        time += self.deltaTime
    }

    func reset() {
        time = 0
        deltaTime = Self.defaultDeltaTime
    }
}
