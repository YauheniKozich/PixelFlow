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
        var params = SamplingParams(
            importanceThreshold: 0.15,
            contrastWeight: 0.6,
            saturationWeight: 0.4,
            edgeRadius: 2,
            importantSamplingRatio: 1, // дефолт 0,7
            topBottomRatio: 0.5

        )
        params.applyAntiClustering = false // Отключаем для теста распределения
        return params
    }
}
