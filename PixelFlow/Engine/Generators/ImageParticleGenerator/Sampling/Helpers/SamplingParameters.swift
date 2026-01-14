//
//  SamplingParameters.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation

enum SamplingParameters {
    static func samplingParams(from cfg: ParticleGeneratorConfiguration) -> SamplingParams {
        if let p = (cfg as? ParticleGenerationConfig)?.samplingParams {
            return p
        }
        return SamplingParams(
            importanceThreshold: 0.15, 
            contrastWeight: 0.6,
            saturationWeight: 0.4,
            edgeRadius: 2
        )
    }
}
