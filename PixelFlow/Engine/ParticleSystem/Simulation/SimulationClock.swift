//
//  SimulationClock.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import QuartzCore

final class SimulationClock {
    
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
}
