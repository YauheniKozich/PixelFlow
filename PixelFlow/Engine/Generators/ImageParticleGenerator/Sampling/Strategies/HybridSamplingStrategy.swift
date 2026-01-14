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
        
        // 40% очень важных, 40% средних, 20% равномерных
        let veryImportantCount = Int(Float(targetCount) * 0.4)
        let middleCount = Int(Float(targetCount) * 0.4)
        let uniformCount = targetCount - veryImportantCount - middleCount
        
        // Очень важные (high threshold)
        let highParams = SamplingParams(
            importanceThreshold: params.importanceThreshold * 1.5,
            contrastWeight: params.contrastWeight,
            saturationWeight: params.saturationWeight,
            edgeRadius: params.edgeRadius
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
                edgeRadius: params.edgeRadius
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
            var used = PixelCacheHelper.usedPositions(from: result)
            try AdaptiveSamplingStrategy.addUniformSamplesAvoidingDuplicates(
                to: &result,
                used: &used,
                width: width,
                height: height,
                targetCount: targetCount,
                cache: cache
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
                
                let neighbors = PixelCacheHelper.getNeighborPixels(atX: x, y: y, from: cache)
                let importance = ArtifactPreventionHelper.calculateEnhancedPixelImportance(
                    r: pixel.r, g: pixel.g, b: pixel.b, a: pixel.a,
                    neighbors: neighbors,
                    params: params,
                    dominantColors: dominantColors
                )
                
                if importance >= params.importanceThreshold {
                    candidates.append((
                        x: x,
                        y: y,
                        color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
                        importance: importance
                    ))
                }
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
