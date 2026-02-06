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
            importantSamplingRatio: 0.7,
            topBottomRatio: 0.5

        )
        params.applyAntiClustering = true
        return params
    }

    static func samplingParams(from cfg: ParticleGeneratorConfiguration,
                               analysis: ImageAnalysis?) -> SamplingParams {
        let base = samplingParams(from: cfg)
        guard let analysis,
              let config = cfg as? ParticleGenerationConfig else {
            return base
        }
        switch config.qualityPreset {
        case .high, .ultra:
            let tuning = config.analysisSamplingTuning ?? .default
            return adjust(base: base, analysis: analysis, tuning: tuning)
        case .draft, .standard:
            return base
        }
    }

    // MARK: - Private

    private static func adjust(base: SamplingParams,
                               analysis: ImageAnalysis,
                               tuning: AnalysisSamplingTuning) -> SamplingParams {
        var params = base

        let edge = clamp(analysis.edgeDensity, min: 0, max: 1)
        let contrast = clamp(analysis.contrast, min: 0, max: 1)
        let saturation = clamp(analysis.saturation, min: 0, max: 1)
        let complexity = max(0, min(analysis.complexity, 10))

        let edgeBias = (0.5 - edge) * tuning.edgeBiasStrength
        params.importanceThreshold = clamp(base.importanceThreshold * (1.0 + edgeBias),
                                           min: tuning.importanceThresholdMin,
                                           max: tuning.importanceThresholdMax)

        params.contrastWeight = clamp(base.contrastWeight * (1.0 + tuning.contrastWeightScale * contrast),
                                      min: tuning.weightMin,
                                      max: tuning.weightMax)
        params.saturationWeight = clamp(base.saturationWeight * (1.0 + tuning.saturationWeightScale * saturation),
                                        min: tuning.weightMin,
                                        max: tuning.weightMax)

        let radiusBoost = complexity >= tuning.complexityHigh
        ? tuning.edgeRadiusBoostHigh
        : (complexity >= tuning.complexityMid ? tuning.edgeRadiusBoostMid : 0)
        params.edgeRadius = max(1, base.edgeRadius + radiusBoost)

        let detailBoost = min(tuning.detailBoostMax,
                              (edge + Float(complexity) / 10.0) * tuning.detailBoostScale)
        params.importantSamplingRatio = clamp(base.importantSamplingRatio + detailBoost,
                                              min: tuning.importantRatioMin,
                                              max: tuning.importantRatioMax)

        return params
    }

    private static func clamp(_ value: Float, min: Float, max: Float) -> Float {
        Swift.max(min, Swift.min(max, value))
    }
}
