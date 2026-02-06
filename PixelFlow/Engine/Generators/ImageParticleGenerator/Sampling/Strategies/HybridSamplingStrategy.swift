//
//  HybridSamplingStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics

enum HybridSamplingStrategy {
    
    static func sample(width: Int,
                      height: Int,
                      targetCount: Int,
                      params: SamplingParams,
                      cache: PixelCache,
                      dominantColors: [SIMD3<Float>] = []) throws -> [Sample] {
        
        guard width > 0, height > 0 else { return [] }
        guard params.importantSamplingRatio >= 0 && params.importantSamplingRatio <= 1 else { return [] }
        guard params.topBottomRatio >= 0 && params.topBottomRatio <= 1 else { return [] }
        
        guard targetCount > 0 else { return [] }
        
        let totalPixels = width * height
        if targetCount >= totalPixels {
            return try UniformSamplingStrategy.sample(
                width: width,
                height: height,
                targetCount: totalPixels,
                cache: cache
            )
        }
        
        // Используем params.importantSamplingRatio для расчёта пропорций
        let veryImportantCount = Int(Float(targetCount) * params.importantSamplingRatio)
        let remaining = targetCount - veryImportantCount
        let middleCount = remaining / 2
        let uniformCount = remaining - middleCount
        
        // Очень важные (high threshold)
        let highParams = SamplingParams(
            importanceThreshold: params.importanceThreshold * 1.5,
            contrastWeight: params.contrastWeight,
            saturationWeight: params.saturationWeight,
            edgeRadius: params.edgeRadius,
            importantSamplingRatio: params.importantSamplingRatio,
            topBottomRatio: params.topBottomRatio
        )
        
        var result = try ImportanceSamplingStrategy.sample(
            width: width,
            height: height,
            targetCount: veryImportantCount,
            params: highParams,
            cache: cache,
            dominantColors: dominantColors
        )
        
        // Средне важные (low threshold)
        if result.count < targetCount {
            let lowParams = SamplingParams(
                importanceThreshold: params.importanceThreshold * 0.5,
                contrastWeight: params.contrastWeight,
                saturationWeight: params.saturationWeight,
                edgeRadius: params.edgeRadius,
                importantSamplingRatio: params.importantSamplingRatio,
                topBottomRatio: params.topBottomRatio
            )
            
            var used = PixelCacheHelper.usedPositions(from: result)
            try addImportantSamplesAvoidingDuplicates(
                to: &result,
                used: &used,
                width: width,
                height: height,
                targetCount: veryImportantCount + middleCount,
                params: lowParams,
                cache: cache,
                dominantColors: dominantColors
            )
        }
        
        // Заполняем оставшиеся равномерно
        if result.count < targetCount && uniformCount > 0 {
            let used = PixelCacheHelper.usedPositions(from: result)
            var colorCache: [SIMD4<Float>] = []
            colorCache.reserveCapacity(width * height)
            for y in 0..<height {
                for x in 0..<width {
                    if let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) {
                        colorCache.append(SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a))
                    } else {
                        colorCache.append(SIMD4<Float>(0, 0, 0, 0))
                    }
                }
            }
            // Преобразуем Set<UInt64> used в [Bool] usedArray
            var usedArray = [Bool](repeating: false, count: width * height)
            for key in used {
                let x = Int(key & 0xFFFFFFFF)
                let y = Int((key >> 32) & 0xFFFFFFFF)
                if x >= 0 && x < width && y >= 0 && y < height {
                    usedArray[y * width + x] = true
                }
            }
            try AdaptiveSamplingStrategy.addBalancedUniformSamples(
                to: &result,
                used: &usedArray,
                width: width,
                height: height,
                targetCount: targetCount,
                cache: cache,
                colorCache: colorCache,
                topBottomRatio: params.topBottomRatio
                
            )
        }
        
        return result
    }
    
    private static func addImportantSamplesAvoidingDuplicates(to samples: inout [Sample],
                                                             used: inout Set<UInt64>,
                                                             width: Int,
                                                             height: Int,
                                                             targetCount: Int,
                                                             params: SamplingParams,
                                                             cache: PixelCache,
                                                             dominantColors: [SIMD3<Float>] = []) throws {
        
        let needed = targetCount - samples.count
        guard needed > 0 else { return }
        
        let scanStrideX = max(1, width / 200)
        let scanStrideY = max(1, height / 200)
        
        var candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] = []
        
        for y in stride(from: 0, to: height, by: scanStrideY) {
            for x in stride(from: 0, to: width, by: scanStrideX) {
                let key = PixelCacheHelper.positionKey(x, y)
                if used.contains(key) { continue }
                
                guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else { continue }
                guard pixel.a > PixelCacheHelper.Constants.alphaThreshold else { continue }
                
                _ = PixelCacheHelper.getNeighborPixels(atX: x, y: y, from: cache)
            }
        }
        
        candidates.sort { $0.importance > $1.importance }
        
        for candidate in candidates.prefix(needed) {
            let key = PixelCacheHelper.positionKey(candidate.x, candidate.y)
            used.insert(key)
            samples.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
        }
    }
}
