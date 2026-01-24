//
//  SimulationClock.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Класс для управления временем симуляции
//

import Foundation
import QuartzCore

/// Протокол для управления временем симуляции
protocol SimulationClockProtocol {
    var time: Float { get }
    var deltaTime: Float { get }
    
    func update()
    func update(with deltaTime: Float)
    func reset()
}

/// Дефолтная реализация SimulationClockProtocol с использованием CACurrentMediaTime
final class DefaultSimulationClock: SimulationClockProtocol {
    private static let defaultDeltaTime: Float = 1.0 / 60.0
    private(set) var time: Float = 0
    private(set) var deltaTime: Float = defaultDeltaTime
    private var lastTimestamp: CFTimeInterval = 0
    private var updateCount: Int = 0
    
    func update() {
        updateCount += 1
           let oldTime = time 
           let now = CACurrentMediaTime()
           let dt = lastTimestamp > 0 ? Float(now - lastTimestamp) : deltaTime
           lastTimestamp = now
           
           deltaTime = min(max(dt, 1e-4), 0.1)
           time += deltaTime
           
           // Логирование первых 5 вызовов и каждый 60-й
           if updateCount <= 5 || updateCount == 60 || updateCount == 120 {
               print("DefaultSimulationClock.update() #\(updateCount): oldTime=\(oldTime), newTime=\(time), dt=\(dt), deltaTime=\(deltaTime)")
           }
    }
    
    func update(with deltaTime: Float) {
        self.deltaTime = min(max(deltaTime, 1e-4), 0.1)
        time += self.deltaTime
    }
    
    func reset() {
        time = 0
        deltaTime = Self.defaultDeltaTime
        lastTimestamp = 0
    }
}
