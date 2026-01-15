//
//  SamplingParams.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation

struct SamplingParams {
    let importanceThreshold: Float
    let contrastWeight: Float
    let saturationWeight: Float
    let edgeRadius: Int
    let importantSamplingRatio: Float
    let topBottomRatio: Float
    var applyAntiClustering: Bool = true
    
    init(importanceThreshold: Float,
         contrastWeight: Float,
         saturationWeight: Float,
         edgeRadius: Int,
         importantSamplingRatio: Float,
         topBottomRatio: Float) {
        self.importanceThreshold = importanceThreshold
        self.contrastWeight = contrastWeight
        self.saturationWeight = saturationWeight
        self.edgeRadius = edgeRadius
        self.importantSamplingRatio = importantSamplingRatio
        self.topBottomRatio = topBottomRatio
    }
}
