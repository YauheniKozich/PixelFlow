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
    
    init(importanceThreshold: Float,
         contrastWeight: Float,
         saturationWeight: Float,
         edgeRadius: Int) {
        self.importanceThreshold = importanceThreshold
        self.contrastWeight = contrastWeight
        self.saturationWeight = saturationWeight
        self.edgeRadius = edgeRadius
    }
}
