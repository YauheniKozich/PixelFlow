//
//  AdaptiveSamplingStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics

enum AdaptiveSamplingStrategy {
    
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
        
        // 70% важных + 30% равномерных
        let importantCount = Int(Float(targetCount) * 0.7)
        let uniformCount = targetCount - importantCount
        
        var result = try ImportanceSamplingStrategy.sample(
            width: width,
            height: height,
            targetCount: importantCount,
            params: params,
            cache: cache,
            dominantColors: dominantColors
        )
        
        var used = PixelCacheHelper.usedPositions(from: result)
        
        if result.count < targetCount && uniformCount > 0 {
            try addUniformSamplesAvoidingDuplicates(
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
    
    static func addUniformSamplesAvoidingDuplicates(to samples: inout [Sample],
                                                           used: inout Set<UInt64>,
                                                           width: Int,
                                                           height: Int,
                                                           targetCount: Int,
                                                           cache: PixelCache) throws {
        
        let needed = targetCount - samples.count
        guard needed > 0 else { return }
        
        let stepX = max(1, width / 100)
        let stepY = max(1, height / 100)
        
        outerLoop: for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                if samples.count >= targetCount { break outerLoop }
                let key = PixelCacheHelper.positionKey(x, y)
                if used.insert(key).inserted {
                    samples.append(Sample(x: x, y: y, color: cache.color(atX: x, y: y)))
                }
            }
        }
        
        if samples.count < targetCount {
            try addRandomSamples(
                to: &samples,
                width: width,
                height: height,
                targetCount: targetCount,
                cache: cache
            )
        }
    }
    
    private static func addRandomSamples(to samples: inout [Sample],
                                        width: Int,
                                        height: Int,
                                        targetCount: Int,
                                        cache: PixelCache) throws {
        
        var used = PixelCacheHelper.usedPositions(from: samples)
        let needed = targetCount - samples.count
        var attempts = 0
        let maxAttempts = needed * 5
        
        while samples.count < targetCount && attempts < maxAttempts {
            let x = Int.random(in: 0..<width)
            let y = Int.random(in: 0..<height)
            let key = PixelCacheHelper.positionKey(x, y)
            if used.insert(key).inserted {
                samples.append(Sample(x: x, y: y, color: cache.color(atX: x, y: y)))
            }
            attempts += 1
        }
        
        if samples.count < targetCount {
            Logger.shared.warning("Не удалось сгенерировать достаточное количество уникальных случайных сэмплов (\(samples.count)/\(targetCount))")
        }
    }
}
