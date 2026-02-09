//
//  AdaptiveSamplingStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics

enum AdaptiveSamplingStrategy {
    
    // MARK: - Public Interface
    
    static func sample(
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>] = []
    ) throws -> [Sample] {
        
        guard targetCount > 0 else { return [] }
        
        if shouldUseFallbackStrategy(targetCount: targetCount, width: width, height: height) {
            return try fallbackToUniformSampling(
                width: width,
                height: height,
                targetCount: targetCount,
                cache: cache
            )
        }
        
        let colorCache = createColorCache(width: width, height: height, cache: cache)
        
        var samples = try generateImportanceSamples(
            width: width,
            height: height,
            targetCount: targetCount,
            params: params,
            cache: cache,
            dominantColors: dominantColors
        )
        
        #if DEBUG
        logSampleDistribution(samples, height: height, stage: "После ImportanceSampling")
        #endif
        
        var used = createUsageMap(from: samples, width: width)
        
        if samples.count < targetCount {
            try fillRemainingSlots(
                samples: &samples,
                used: &used,
                width: width,
                height: height,
                targetCount: targetCount,
                params: params,
                cache: cache,
                colorCache: colorCache
            )
        }
        
        #if DEBUG
        logSampleDistribution(samples, height: height, stage: "После добавления uniform")
        #endif
        
        return samples
    }
    
    // MARK: - Strategy Selection
    
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
    
    // MARK: - Color Cache
    
    private static func createColorCache(
        width: Int,
        height: Int,
        cache: PixelCache
    ) -> [SIMD4<Float>] {
        let totalPixels = width * height
        var colorCache = [SIMD4<Float>](
            repeating: SIMD4<Float>(0, 0, 0, 0),
            count: totalPixels
        )
        
        for y in 0..<height {
            for x in 0..<width {
                colorCache[y * width + x] = cache.color(atX: x, y: y)
            }
        }
        
        return colorCache
    }
    
    // MARK: - Importance Sampling
    
    private static func generateImportanceSamples(
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>]
    ) throws -> [Sample] {
        let importantCount = calculateImportantCount(
            targetCount: targetCount,
            ratio: params.importantSamplingRatio
        )
        
        return try ImportanceSamplingStrategy.sample(
            width: width,
            height: height,
            targetCount: importantCount,
            params: params,
            cache: cache,
            dominantColors: dominantColors
        )
    }
    
    private static func calculateImportantCount(
        targetCount: Int,
        ratio: Float
    ) -> Int {
        return Int(Float(targetCount) * ratio)
    }
    
    // MARK: - Usage Tracking
    
    private static func createUsageMap(from samples: [Sample], width: Int) -> [Bool] {
        let totalPixels = samples.map { $0.y * width + $0.x }.max().map { $0 + 1 } ?? 0
        var used = [Bool](repeating: false, count: max(totalPixels, width))
        
        for sample in samples {
            used[sample.y * width + sample.x] = true
        }
        
        return used
    }
    
    // MARK: - Sample Filling
    
    private static func fillRemainingSlots(
        samples: inout [Sample],
        used: inout [Bool],
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        colorCache: [SIMD4<Float>]
    ) throws {
        let uniformCount = targetCount - samples.count
        guard uniformCount > 0 else { return }
        
        try addBalancedUniformSamples(
            to: &samples,
            used: &used,
            width: width,
            height: height,
            targetCount: targetCount,
            cache: cache,
            colorCache: colorCache,
            topBottomRatio: params.topBottomRatio
        )
    }
    
    // MARK: - Balanced Uniform Sampling
    
    /// Сбалансированное добавление uniform сэмплов
    static func addBalancedUniformSamples(
        to samples: inout [Sample],
        used: inout [Bool],
        width: Int,
        height: Int,
        targetCount: Int,
        cache: PixelCache,
        colorCache: [SIMD4<Float>],
        topBottomRatio: Float
    ) throws {
        
        let needed = targetCount - samples.count
        guard needed > 0 else { return }
        
        if samples.count < targetCount {
            try addRemainingRandomSamples(
                to: &samples,
                used: &used,
                width: width,
                height: height,
                targetCount: targetCount,
                cache: cache,
                colorCache: colorCache,
                topBottomRatio: topBottomRatio
            )
        }
    }
    
    // MARK: - Distribution Calculation
    
    private struct TargetDistribution {
        let needTop: Int
        let needBottom: Int
        let targetTop: Int
        let targetBottom: Int
    }
    
    private static func calculateTargetDistribution(
        samples: [Sample],
        height: Int,
        targetCount: Int,
        topBottomRatio: Float
    ) -> TargetDistribution {
        let currentTop = countTopSamples(samples, height: height)
        let currentBottom = samples.count - currentTop
        
        let targetTop = Int(Float(targetCount) * topBottomRatio)
        let targetBottom = targetCount - targetTop
        
        let needTop = max(0, targetTop - currentTop)
        let needBottom = max(0, targetBottom - currentBottom)
        
        return TargetDistribution(
            needTop: needTop,
            needBottom: needBottom,
            targetTop: targetTop,
            targetBottom: targetBottom
        )
    }
    
    private static func countTopSamples(_ samples: [Sample], height: Int) -> Int {
        return samples.filter { $0.y < height / 2 }.count
    }
    
    // MARK: - Grid Parameters
    
    private struct GridParameters {
        let stepX: Int
        let stepY: Int
    }
    
    private static func calculateGridParameters(
        needed: Int,
        width: Int,
        height: Int
    ) -> GridParameters {
        let gridSize = Int(ceil(sqrt(Double(needed)) * 1.5))
        let stepX = max(1, width / gridSize)
        let stepY = max(1, (height / 2) / gridSize)
        
        return GridParameters(stepX: stepX, stepY: stepY)
    }
    
    // MARK: - Grid Sampling
    
    private struct AddedCounts {
        var top: Int
        var bottom: Int
    }
    
    private static func addGridSamples(
        to samples: inout [Sample],
        used: inout [Bool],
        width: Int,
        height: Int,
        distribution: TargetDistribution,
        gridParams: GridParameters,
        colorCache: [SIMD4<Float>]
    ) -> AddedCounts {
        
        var counts = AddedCounts(top: 0, bottom: 0)
        
        if distribution.needTop > 0 {
            counts.top = addGridSamplesInRegion(
                to: &samples,
                used: &used,
                width: width,
                yRange: 0..<(height / 2),
                stepX: gridParams.stepX,
                stepY: gridParams.stepY,
                maxCount: distribution.needTop,
                colorCache: colorCache
            )
        }
        
        if distribution.needBottom > 0 {
            counts.bottom = addGridSamplesInRegion(
                to: &samples,
                used: &used,
                width: width,
                yRange: (height / 2)..<height,
                stepX: gridParams.stepX,
                stepY: gridParams.stepY,
                maxCount: distribution.needBottom,
                colorCache: colorCache
            )
        }
        
        return counts
    }
    
    private static func addGridSamplesInRegion(
        to samples: inout [Sample],
        used: inout [Bool],
        width: Int,
        yRange: Range<Int>,
        stepX: Int,
        stepY: Int,
        maxCount: Int,
        colorCache: [SIMD4<Float>]
    ) -> Int {
        
        var added = 0
        
        outerLoop: for y in stride(from: yRange.lowerBound, to: yRange.upperBound, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                if added >= maxCount { break outerLoop }
                
                let keyIndex = y * width + x
                guard keyIndex < used.count, keyIndex < colorCache.count else { continue }
                
                if !used[keyIndex] {
                    used[keyIndex] = true
                    samples.append(Sample(x: x, y: y, color: colorCache[keyIndex]))
                    added += 1
                }
            }
        }
        
        return added
    }
    
    // MARK: - Random Sampling
    
    private static func addRemainingRandomSamples(
        to samples: inout [Sample],
        used: inout [Bool],
        width: Int,
        height: Int,
        targetCount: Int,
        cache: PixelCache,
        colorCache: [SIMD4<Float>],
        topBottomRatio: Float
    ) throws {
        
        let stillNeeded = targetCount - samples.count
        guard stillNeeded > 0 else { return }
        
        try addBalancedRandomSamples(
            to: &samples,
            used: &used,
            width: width,
            height: height,
            needed: stillNeeded,
            cache: cache,
            colorCache: colorCache,
            topBottomRatio: topBottomRatio
        )
    }
    
    /// Сбалансированные случайные сэмплы с streaming выборкой
    private static func addBalancedRandomSamples(
        to samples: inout [Sample],
        used: inout [Bool],
        width: Int,
        height: Int,
        needed: Int,
        cache: PixelCache,
        colorCache: [SIMD4<Float>],
        topBottomRatio: Float
    ) throws {
        
        let ratio = clampRatio(topBottomRatio)
        
        let freePositions = collectFreePositions(
            used: used,
            width: width,
            height: height
        )
        
        let addedCounts = addRandomSamplesWithBalance(
            to: &samples,
            used: &used,
            width: width,
            height: height,
            needed: needed,
            freePositions: freePositions,
            ratio: ratio,
            colorCache: colorCache
        )
        
        if addedCounts.total < needed {
            Logger.shared.warning("Не удалось добавить все случайные сэмплы (\(addedCounts.total)/\(needed))")
        }
    }
    
    private static func clampRatio(_ ratio: Float) -> Float {
        return min(max(ratio, 0.0), 1.0)
    }
    
    // MARK: - Free Position Collection
    
    private struct FreePositions {
        var top: [(Int, Int)]
        var bottom: [(Int, Int)]
    }
    
    private static func collectFreePositions(
        used: [Bool],
        width: Int,
        height: Int
    ) -> FreePositions {
        
        var positions = FreePositions(top: [], bottom: [])
        
        for y in 0..<height {
            let isTop = y < height / 2
            for x in 0..<width {
                let index = y * width + x
                guard index < used.count else { continue }
                
                if !used[index] {
                    if isTop {
                        positions.top.append((x, y))
                    } else {
                        positions.bottom.append((x, y))
                    }
                }
            }
        }
        
        return positions
    }
    
    // MARK: - Balanced Random Addition
    
    private struct RandomAddedCounts {
        var top: Int
        var bottom: Int
        
        var total: Int { top + bottom }
    }
    
    private static func addRandomSamplesWithBalance(
        to samples: inout [Sample],
        used: inout [Bool],
        width: Int,
        height: Int,
        needed: Int,
        freePositions: FreePositions,
        ratio: Float,
        colorCache: [SIMD4<Float>]
    ) -> RandomAddedCounts {
        
        var positions = freePositions
        var counts = RandomAddedCounts(top: 0, bottom: 0)
        var topIndex = 0
        var bottomIndex = 0
        
        let currentTop = countTopSamples(samples, height: height)
        
        while counts.total < needed {
            let totalSamples = samples.count + 1
            let topRatioCurrent = Float(currentTop + counts.top) / Float(totalSamples)
            let shouldAddTop = topRatioCurrent < ratio
            
            if shouldAddTop && topIndex < positions.top.count {
                addRandomSample(
                    to: &samples,
                    used: &used,
                    width: width,
                    positions: &positions.top,
                    index: &topIndex,
                    addedCount: &counts.top,
                    colorCache: colorCache
                )
            } else if !shouldAddTop && bottomIndex < positions.bottom.count {
                addRandomSample(
                    to: &samples,
                    used: &used,
                    width: width,
                    positions: &positions.bottom,
                    index: &bottomIndex,
                    addedCount: &counts.bottom,
                    colorCache: colorCache
                )
            } else {
                // Если не хватает позиций в нужной половине, пытаемся из другой
                if topIndex < positions.top.count {
                    addRandomSample(
                        to: &samples,
                        used: &used,
                        width: width,
                        positions: &positions.top,
                        index: &topIndex,
                        addedCount: &counts.top,
                        colorCache: colorCache
                    )
                } else if bottomIndex < positions.bottom.count {
                    addRandomSample(
                        to: &samples,
                        used: &used,
                        width: width,
                        positions: &positions.bottom,
                        index: &bottomIndex,
                        addedCount: &counts.bottom,
                        colorCache: colorCache
                    )
                } else {
                    // Нет свободных позиций
                    break
                }
            }
        }
        
        return counts
    }
    
    private static func addRandomSample(
        to samples: inout [Sample],
        used: inout [Bool],
        width: Int,
        positions: inout [(Int, Int)],
        index: inout Int,
        addedCount: inout Int,
        colorCache: [SIMD4<Float>]
    ) {
        let swapIndex = index + Int.random(in: 0..<(positions.count - index))
        positions.swapAt(index, swapIndex)
        
        let (x, y) = positions[index]
        index += 1
        
        let keyIndex = y * width + x
        guard keyIndex < used.count, keyIndex < colorCache.count else { return }
        
        used[keyIndex] = true
        samples.append(Sample(x: x, y: y, color: colorCache[keyIndex]))
        addedCount += 1
    }
    
    // MARK: - Debug Logging
    
    #if DEBUG
    private static func logSampleDistribution(
        _ samples: [Sample],
        height: Int,
        stage: String
    ) {
        let topCount = countTopSamples(samples, height: height)
        let bottomCount = samples.count - topCount
        Logger.shared.debug("\(stage) (\(samples.count)): Top \(topCount), Bottom \(bottomCount)")
    }
    #endif
}
