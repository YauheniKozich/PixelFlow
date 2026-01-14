//
//  UniformSamplingStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics
import simd

enum UniformSamplingStrategy {
    
    static func sample(width: Int,
                      height: Int,
                      targetCount: Int,
                      cache: PixelCache) throws -> [Sample] {
        
        let totalPixels = width * height
        guard targetCount > 0 else { return [] }
        
        var result: [Sample] = []
        
        if targetCount >= totalPixels {
            result.reserveCapacity(totalPixels)
            for y in 0..<height {
                for x in 0..<width {
                    result.append(Sample(x: x, y: y, color: cache.color(atX: x, y: y)))
                }
            }
            Logger.shared.debug("Униформное сэмплирование: взяты все \(totalPixels) пикселей.")
            return result
        }
        
        result.reserveCapacity(targetCount)
        let step = max(1, Int(ceil(Double(totalPixels) / Double(targetCount))))
        var index = 0
        
        while result.count < targetCount && index < totalPixels {
            let x = index % width
            let y = index / width
            result.append(Sample(x: x, y: y, color: cache.color(atX: x, y: y)))
            index += step
        }
        
        Logger.shared.debug("Униформное сэмплирование: сгенерировано \(result.count) сэмплов (шаг: \(step))")
        return result
    }
}
