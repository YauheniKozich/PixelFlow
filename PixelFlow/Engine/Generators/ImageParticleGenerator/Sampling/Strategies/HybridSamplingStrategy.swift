//
//  HybridSamplingStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics

enum HybridSamplingStrategy {
    
    // MARK: - Public Interface
    
    static func sample(
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>] = []
    ) throws -> [Sample] {
        
        // Валидация входных данных
        guard width > 0, height > 0 else { return [] }
        guard params.importantSamplingRatio >= 0 && params.importantSamplingRatio <= 1 else { return [] }
        guard params.topBottomRatio >= 0 && params.topBottomRatio <= 1 else { return [] }
        guard targetCount > 0 else { return [] }
        
        if shouldUseFallbackStrategy(targetCount: targetCount, width: width, height: height) {
            return try fallbackToUniformSampling(
                width: width,
                height: height,
                targetCount: targetCount,
                cache: cache
            )
        }
        
        let distribution = calculateSampleDistribution(
            targetCount: targetCount,
            importantRatio: params.importantSamplingRatio
        )
        
        var samples = try generateHighImportanceSamples(
            width: width,
            height: height,
            targetCount: distribution.veryImportant,
            params: params,
            cache: cache,
            dominantColors: dominantColors
        )
        
        if samples.count < targetCount {
            try addMediumImportanceSamples(
                to: &samples,
                width: width,
                height: height,
                targetCount: distribution.veryImportant + distribution.middle,
                params: params,
                cache: cache,
                dominantColors: dominantColors
            )
        }
        
        if samples.count < targetCount && distribution.uniform > 0 {
            try fillWithUniformSamples(
                samples: &samples,
                width: width,
                height: height,
                targetCount: targetCount,
                params: params,
                cache: cache
            )
        }
        
        return samples
    }
    
    private static func shouldUseFallbackStrategy(
        targetCount: Int,
        width: Int,
        height: Int
    ) -> Bool {
        let totalPixels = width * height
        return targetCount >= totalPixels
    }
    
    private static func fallbackToUniformSampling(
        width: Int,
        height: Int,
        targetCount: Int,
        cache: PixelCache
    ) throws -> [Sample] {
        let totalPixels = width * height
        return try UniformSamplingStrategy.sample(
            width: width,
            height: height,
            targetCount: totalPixels,
            cache: cache
        )
    }
    
    // MARK: - Distribution Calculation
    
    private struct SampleDistribution {
        let veryImportant: Int
        let middle: Int
        let uniform: Int
    }
    
    private static func calculateSampleDistribution(
        targetCount: Int,
        importantRatio: Float
    ) -> SampleDistribution {
        let veryImportantCount = Int(Float(targetCount) * importantRatio)
        let remaining = targetCount - veryImportantCount
        let middleCount = remaining / 2
        let uniformCount = remaining - middleCount
        
        return SampleDistribution(
            veryImportant: veryImportantCount,
            middle: middleCount,
            uniform: uniformCount
        )
    }
    
    // MARK: - High Importance Sampling
    
    private static func generateHighImportanceSamples(
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>]
    ) throws -> [Sample] {
        
        let highParams = createHighImportanceParams(from: params)
        
        return try ImportanceSamplingStrategy.sample(
            width: width,
            height: height,
            targetCount: targetCount,
            params: highParams,
            cache: cache,
            dominantColors: dominantColors
        )
    }
    
    private static func createHighImportanceParams(from params: SamplingParams) -> SamplingParams {
        return SamplingParams(
            importanceThreshold: params.importanceThreshold * 1.5,
            contrastWeight: params.contrastWeight,
            saturationWeight: params.saturationWeight,
            edgeRadius: params.edgeRadius,
            importantSamplingRatio: params.importantSamplingRatio,
            topBottomRatio: params.topBottomRatio
        )
    }
    
    // MARK: - Medium Importance Sampling
    
    private static func addMediumImportanceSamples(
        to samples: inout [Sample],
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>]
    ) throws {
        
        let lowParams = createLowImportanceParams(from: params)
        var used = PixelCacheHelper.usedPositions(from: samples)
        
        try addImportantSamplesAvoidingDuplicates(
            to: &samples,
            used: &used,
            width: width,
            height: height,
            targetCount: targetCount,
            params: lowParams,
            cache: cache,
            dominantColors: dominantColors
        )
    }
    
    private static func createLowImportanceParams(from params: SamplingParams) -> SamplingParams {
        return SamplingParams(
            importanceThreshold: params.importanceThreshold * 0.5,
            contrastWeight: params.contrastWeight,
            saturationWeight: params.saturationWeight,
            edgeRadius: params.edgeRadius,
            importantSamplingRatio: params.importantSamplingRatio,
            topBottomRatio: params.topBottomRatio
        )
    }
    
    // MARK: - Uniform Fill
    
    private static func fillWithUniformSamples(
        samples: inout [Sample],
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache
    ) throws {
        
        let used = PixelCacheHelper.usedPositions(from: samples)
        let colorCache = createColorCache(width: width, height: height, cache: cache)
        let usedArray = convertUsedSetToArray(
            used: used,
            width: width,
            height: height
        )
        
        var mutableUsedArray = usedArray
        
        try AdaptiveSamplingStrategy.addBalancedUniformSamples(
            to: &samples,
            used: &mutableUsedArray,
            width: width,
            height: height,
            targetCount: targetCount,
            cache: cache,
            colorCache: colorCache,
            topBottomRatio: params.topBottomRatio
        )
    }
    
    private static func createColorCache(
        width: Int,
        height: Int,
        cache: PixelCache
    ) -> [SIMD4<Float>] {
        
        let totalPixels = width * height
        var colorCache: [SIMD4<Float>] = []
        colorCache.reserveCapacity(totalPixels)
        
        for y in 0..<height {
            for x in 0..<width {
                let color = extractPixelColor(x: x, y: y, cache: cache)
                colorCache.append(color)
            }
        }
        
        return colorCache
    }
    
    private static func extractPixelColor(x: Int, y: Int, cache: PixelCache) -> SIMD4<Float> {
        guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else {
            return SIMD4<Float>(0, 0, 0, 0)
        }
        return SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a)
    }
    
    private static func convertUsedSetToArray(
        used: Set<UInt64>,
        width: Int,
        height: Int
    ) -> [Bool] {
        
        var usedArray = [Bool](repeating: false, count: width * height)
        
        for key in used {
            let (x, y) = decodePositionKey(key)
            if isValidPosition(x: x, y: y, width: width, height: height) {
                usedArray[y * width + x] = true
            }
        }
        
        return usedArray
    }
    
    private static func decodePositionKey(_ key: UInt64) -> (x: Int, y: Int) {
        let x = Int(key & 0xFFFFFFFF)
        let y = Int((key >> 32) & 0xFFFFFFFF)
        return (x, y)
    }
    
    private static func isValidPosition(x: Int, y: Int, width: Int, height: Int) -> Bool {
        return x >= 0 && x < width && y >= 0 && y < height
    }
    
    // MARK: - Duplicate Avoidance
    
    private static func addImportantSamplesAvoidingDuplicates(
        to samples: inout [Sample],
        used: inout Set<UInt64>,
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>] = []
    ) throws {
        
        let needed = targetCount - samples.count
        guard needed > 0 else { return }
        
        let candidates = collectCandidates(
            width: width,
            height: height,
            used: used,
            cache: cache
        )
        
        let sortedCandidates = candidates.sorted { $0.importance > $1.importance }
        
        addTopCandidates(
            sortedCandidates,
            count: needed,
            to: &samples,
            used: &used
        )
    }
    
    private struct Candidate {
        let x: Int
        let y: Int
        let color: SIMD4<Float>
        let importance: Float
    }
    
    private static func collectCandidates(
        width: Int,
        height: Int,
        used: Set<UInt64>,
        cache: PixelCache
    ) -> [Candidate] {
        
        let scanStride = calculateScanStride(width: width, height: height)
        var candidates: [Candidate] = []
        
        for y in stride(from: 0, to: height, by: scanStride.y) {
            for x in stride(from: 0, to: width, by: scanStride.x) {
                if let candidate = tryCreateCandidate(
                    x: x,
                    y: y,
                    used: used,
                    cache: cache
                ) {
                    candidates.append(candidate)
                }
            }
        }
        
        return candidates
    }
    
    private struct ScanStride {
        let x: Int
        let y: Int
    }
    
    private static func calculateScanStride(width: Int, height: Int) -> ScanStride {
        return ScanStride(
            x: max(1, width / 200),
            y: max(1, height / 200)
        )
    }
    
    private static func tryCreateCandidate(
        x: Int,
        y: Int,
        used: Set<UInt64>,
        cache: PixelCache
    ) -> Candidate? {
        
        let key = PixelCacheHelper.positionKey(x, y)
        guard !used.contains(key) else { return nil }
        
        guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else {
            return nil
        }
        
        guard pixel.a > PixelCacheHelper.Constants.alphaThreshold else {
            return nil
        }
        
        // Получаем соседей для потенциальных будущих вычислений важности
        _ = PixelCacheHelper.getNeighborPixels(atX: x, y: y, from: cache)
        
        let color = SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a)
        let importance = calculateImportance(pixel: pixel)
        
        return Candidate(x: x, y: y, color: color, importance: importance)
    }
    
    private static func calculateImportance(pixel: (r: Float, g: Float, b: Float, a: Float)) -> Float {
        // Простой расчёт важности на основе яркости и насыщенности
        let brightness = (pixel.r + pixel.g + pixel.b) / 3.0
        let maxC = max(pixel.r, max(pixel.g, pixel.b))
        let minC = min(pixel.r, min(pixel.g, pixel.b))
        let saturation = maxC > 0 ? (maxC - minC) / maxC : 0
        
        return brightness * 0.6 + saturation * 0.4
    }
    
    private static func addTopCandidates(
        _ candidates: [Candidate],
        count: Int,
        to samples: inout [Sample],
        used: inout Set<UInt64>
    ) {
        
        for candidate in candidates.prefix(count) {
            let key = PixelCacheHelper.positionKey(candidate.x, candidate.y)
            used.insert(key)
            samples.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
        }
    }
}
