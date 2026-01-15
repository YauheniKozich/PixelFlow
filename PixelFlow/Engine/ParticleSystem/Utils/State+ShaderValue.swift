//
//  State+ShaderValue.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 10.01.26.
//

import Foundation

extension SimulationState {
    var shaderValue: UInt32 {
        switch self {
        case .idle: return 0
        case .chaotic: return 1
        case .collecting: return 2
        case .collected: return 3
        case .lightningStorm: return 4
        }
    }
}
