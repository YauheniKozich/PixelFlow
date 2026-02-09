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
        
        // Если нужно больше или равно всем пикселям — берем все
        if targetCount >= totalPixels {
            result.reserveCapacity(totalPixels)
            for y in 0..<height {
                for x in 0..<width {
                    result.append(Sample(x: x, y: y, color: cache.color(atX: x, y: y)))
                }
            }
            return result
        }
        
        // 2D-сетка для равномерного покрытия (предотвращает пропуск строк)
        result.reserveCapacity(targetCount)
        
        let aspectRatio = Double(width) / Double(height)
        let gridHeight = max(1, Int(sqrt(Double(targetCount) / aspectRatio)))
        let gridWidth = max(1, Int(ceil(Double(targetCount) / Double(gridHeight))))
        
        var samplesGenerated = 0

        // Равномерные координаты, включая края (чтобы не было "пустых" полос сверху/снизу)
        @inline(__always)
        func gridCoord(_ index: Int, _ gridSize: Int, _ maxCoord: Int) -> Int {
            guard gridSize > 1 else { return maxCoord / 2 }
            let t = Double(index) / Double(gridSize - 1)
            return Int((t * Double(maxCoord)).rounded())
        }
        
        outerLoop: for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                guard samplesGenerated < targetCount else { break outerLoop }
                
                // Координаты по краям включительно (избегаем пропусков сверху/снизу)
                let x = gridCoord(gx, gridWidth, max(0, width - 1))
                let y = gridCoord(gy, gridHeight, max(0, height - 1))
                
                // Защита от выхода за границы
                let clampedX = min(x, width - 1)
                let clampedY = min(y, height - 1)
                
                result.append(Sample(x: clampedX, y: clampedY, color: cache.color(atX: clampedX, y: clampedY)))
                samplesGenerated += 1
            }
        }
        
        return result
    }
}
