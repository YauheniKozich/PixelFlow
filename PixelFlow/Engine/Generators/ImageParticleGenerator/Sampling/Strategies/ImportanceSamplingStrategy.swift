//
//  ImportanceSamplingStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics
import simd

enum ImportanceSamplingStrategy {
    
    // MARK: - Constants
    
    private enum Constants {
        static let maxScanDimension = 512
        static let minScanDivider = 16
        static let maxReserveCapacity = 100_000
        static let whiteBackgroundBrightness: Float = 0.95
        static let whiteBackgroundSaturation: Float = 0.05
        static let fallbackImportance: Float = 0.1
    }
    
    // MARK: - Public Interface
    
    static func sample(
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>] = []
    ) throws -> [Sample] {
        
        guard validateInputs(width: width, height: height, targetCount: targetCount, params: params) else {
            return []
        }
        
        Logger.shared.info("Sampling started: width=\(width), height=\(height), targetCount=\(targetCount), params=\(params)")
        
        if shouldUseFallbackStrategy(targetCount: targetCount, width: width, height: height) {
            return try fallbackToUniformSampling(
                width: width,
                height: height,
                cache: cache
            )
        }
        
        let scanStride = calculateScanStride(width: width, height: height)
        
        var candidates = gatherImportantPixels(
            cache: cache,
            width: width,
            height: height,
            scanStride: scanStride,
            params: params,
            dominantColors: dominantColors,
            targetCount: targetCount
        )
        
        logImportanceMetrics(candidates)
        
        candidates = ensureSufficientCandidates(
            candidates: candidates,
            cache: cache,
            width: width,
            height: height,
            targetCount: targetCount
        )
        
        if candidates.count <= targetCount {
            return convertAllCandidatesToSamples(candidates)
        }
        
        let finalSamples = selectBalancedSamples(
            candidates: candidates,
            desiredCount: targetCount,
            height: height,
            topBottomRatio: params.topBottomRatio
        )
        
        Logger.shared.info("Возврат \(finalSamples.count) окончательных сэмплов")
        return finalSamples
    }
    
    // MARK: - Validation
    
    private static func validateInputs(
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams
    ) -> Bool {
        
        guard width > 0, height > 0 else {
            Logger.shared.error("Invalid image dimensions: width and height must be positive")
            return false
        }
        
        guard targetCount > 0 else {
            return false
        }
        
        guard params.isValid else {
            Logger.shared.error("Invalid SamplingParams provided")
            return false
        }
        
        return true
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
    
    // MARK: - Scan Stride Calculation
    
    private struct ScanStride {
        let x: Int
        let y: Int
    }
    
    private static func calculateScanStride(width: Int, height: Int) -> ScanStride {
        let strideX = max(1, min(
            width / Constants.maxScanDimension,
            width / Constants.minScanDivider
        ))
        let strideY = max(1, min(
            height / Constants.maxScanDimension,
            height / Constants.minScanDivider
        ))
        
        return ScanStride(x: strideX, y: strideY)
    }
    
    // MARK: - Candidate Collection
    
    private typealias Candidate = (x: Int, y: Int, color: SIMD4<Float>, importance: Float)
    
    private static func gatherImportantPixels(
        cache: PixelCache,
        width: Int,
        height: Int,
        scanStride: ScanStride,
        params: SamplingParams,
        dominantColors: [SIMD3<Float>],
        targetCount: Int
    ) -> [Candidate] {
        
        let estimatedCapacity = calculateEstimatedCapacity(
            width: width,
            height: height,
            scanStride: scanStride
        )
        
        var candidates: [Candidate] = []
        candidates.reserveCapacity(estimatedCapacity)
        
        
        candidates = scanImageForCandidates(
            cache: cache,
            width: width,
            height: height,
            scanStride: scanStride,
            params: params,
            dominantColors: dominantColors,
            targetCount: targetCount
        )
        
        if params.applyAntiClustering {
            candidates = applyAntiClustering(candidates: candidates, height: height)
        }
        
        return candidates
    }
    
    private static func calculateEstimatedCapacity(
        width: Int,
        height: Int,
        scanStride: ScanStride
    ) -> Int {
        return min(
            (width / scanStride.x) * (height / scanStride.y),
            Constants.maxReserveCapacity
        )
    }
    
    private static func scanImageForCandidates(
        cache: PixelCache,
        width: Int,
        height: Int,
        scanStride: ScanStride,
        params: SamplingParams,
        dominantColors: [SIMD3<Float>],
        targetCount: Int
    ) -> [Candidate] {
        
        var candidates: [Candidate] = []
        
        outer: for y in stride(from: 0, to: height, by: scanStride.y) {
            for x in stride(from: 0, to: width, by: scanStride.x) {
                if let candidate = tryCreateCandidate(
                    x: x,
                    y: y,
                    cache: cache,
                    params: params,
                    dominantColors: dominantColors
                ) {
                    candidates.append(candidate)
                    
                    // Ранний выход, если кандидатов слишком много
                    if candidates.count >= targetCount * 2 {
                        break outer
                    }
                }
            }
        }
        
        return candidates
    }
    
    private static func tryCreateCandidate(
        x: Int,
        y: Int,
        cache: PixelCache,
        params: SamplingParams,
        dominantColors: [SIMD3<Float>]
    ) -> Candidate? {
        
        guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else {
            return nil
        }
        
        guard pixel.a > PixelCacheHelper.Constants.alphaThreshold else {
            return nil
        }
        
        if isWhiteBackground(pixel: pixel) {
            return nil
        }
        
        let neighbors = PixelCacheHelper.getNeighborPixels(atX: x, y: y, from: cache)
        let importance = ArtifactPreventionHelper.calculateEnhancedPixelImportance(
            r: pixel.r, g: pixel.g, b: pixel.b, a: pixel.a,
            neighbors: neighbors,
            params: params,
            dominantColors: dominantColors
        )
        
        guard importance > ArtifactPreventionHelper.Constants.noiseThreshold * 0.5 else {
            return nil
        }
        
        return (
            x: x,
            y: y,
            color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
            importance: importance
        )
    }
    
    private static func isWhiteBackground(pixel: (r: Float, g: Float, b: Float, a: Float)) -> Bool {
        let (brightness, saturation) = calculateBrightnessAndSaturation(pixel: pixel)
        return brightness > Constants.whiteBackgroundBrightness &&
               saturation < Constants.whiteBackgroundSaturation
    }
    
    private static func calculateBrightnessAndSaturation(
        pixel: (r: Float, g: Float, b: Float, a: Float)
    ) -> (brightness: Float, saturation: Float) {
        
        let alpha = pixel.a
        let r = alpha > 0 ? pixel.r / alpha : 0
        let g = alpha > 0 ? pixel.g / alpha : 0
        let b = alpha > 0 ? pixel.b / alpha : 0
        
        let brightness = (r + g + b) / 3.0
        let maxC = max(r, g, b)
        let minC = min(r, g, b)
        let saturation = maxC - minC
        
        return (brightness, saturation)
    }
    
    private static func applyAntiClustering(candidates: [Candidate], height: Int) -> [Candidate] {
        let result = ArtifactPreventionHelper.applyAntiClusteringForCandidates(
            candidates: candidates,
            imageHeight: height
        )
        return result
    }
    
    // MARK: - Candidate Enrichment
    
    private static func ensureSufficientCandidates(
        candidates: [Candidate],
        cache: PixelCache,
        width: Int,
        height: Int,
        targetCount: Int
    ) -> [Candidate] {
        
        let minImportant = max(targetCount / 4, 10)
        
        guard candidates.count < minImportant else {
            return candidates
        }
        
        Logger.shared.warning("Недостаточно важных пикселей (\(candidates.count)), добавляем fallback")
        
        let needed = targetCount - candidates.count
        let fallback = gatherFallbackPixels(
            cache: cache,
            width: width,
            height: height,
            neededCount: needed
        )
        
        return candidates + fallback
    }
    
    private static func gatherFallbackPixels(
        cache: PixelCache,
        width: Int,
        height: Int,
        neededCount: Int
    ) -> [Candidate] {
        
        guard neededCount > 0 else { return [] }
        
        var fallback: [Candidate] = []
        fallback.reserveCapacity(min(neededCount, width * height))
        
        let gridConfig = calculateFallbackGrid(
            width: width,
            height: height,
            neededCount: neededCount
        )
        
        fallback = collectFallbackSamples(
            cache: cache,
            width: width,
            height: height,
            gridConfig: gridConfig,
            neededCount: neededCount
        )
        
        return fallback
    }
    
    private struct FallbackGridConfig {
        let size: Int
        let strideX: Int
        let strideY: Int
    }
    
    private static func calculateFallbackGrid(
        width: Int,
        height: Int,
        neededCount: Int
    ) -> FallbackGridConfig {
        
        let gridSize = Int(ceil(sqrt(Double(neededCount)) * 1.5))
        let strideX = max(1, Int(ceil(Float(width) / Float(gridSize))))
        let strideY = max(1, Int(ceil(Float(height) / Float(gridSize))))
        
        return FallbackGridConfig(
            size: gridSize,
            strideX: strideX,
            strideY: strideY
        )
    }
    
    private static func collectFallbackSamples(
        cache: PixelCache,
        width: Int,
        height: Int,
        gridConfig: FallbackGridConfig,
        neededCount: Int
    ) -> [Candidate] {
        
        var fallback: [Candidate] = []
        
        outer: for gridY in 0..<gridConfig.size {
            for gridX in 0..<gridConfig.size {
                if fallback.count >= neededCount { break outer }
                
                let x = min(gridX * gridConfig.strideX, width - 1)
                let y = min(gridY * gridConfig.strideY, height - 1)
                
                if let candidate = tryCreateFallbackCandidate(
                    x: x,
                    y: y,
                    cache: cache
                ) {
                    fallback.append(candidate)
                }
            }
        }
        
        return fallback
    }
    
    private static func tryCreateFallbackCandidate(
        x: Int,
        y: Int,
        cache: PixelCache
    ) -> Candidate? {
        
        guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else {
            return nil
        }
        
        guard pixel.a > PixelCacheHelper.Constants.lowAlphaThreshold else {
            return nil
        }
        
        return (
            x: x,
            y: y,
            color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
            importance: Constants.fallbackImportance
        )
    }
    
    private static func convertAllCandidatesToSamples(_ candidates: [Candidate]) -> [Sample] {
        let samples = candidates.map { Sample(x: $0.x, y: $0.y, color: $0.color) }
        Logger.shared.info("Возврат \(samples.count) сэмплов (все найденные)")
        return samples
    }
    
    // MARK: - Balanced Selection
    
    private static func selectBalancedSamples(
        candidates: [Candidate],
        desiredCount: Int,
        height: Int,
        topBottomRatio: Float
    ) -> [Sample] {
        
        let (topHalf, bottomHalf) = partitionCandidates(candidates, height: height)
        
        
        guard !topHalf.isEmpty || !bottomHalf.isEmpty else {
            return []
        }
        
        #if DEBUG
        #endif
        
        let targetCounts = calculateTargetCounts(
            desiredCount: desiredCount,
            topBottomRatio: topBottomRatio
        )
        
        let (sortedTop, sortedBottom) = selectTopCandidates(
            topHalf: topHalf,
            bottomHalf: bottomHalf,
            targetCounts: targetCounts
        )
        
        
        var result = combineCandidatesIntoSamples(
            sortedTop: sortedTop,
            sortedBottom: sortedBottom,
            desiredCount: desiredCount
        )
        
        if result.count < desiredCount {
            fillRemainingSlots(
                result: &result,
                sortedTop: sortedTop,
                sortedBottom: sortedBottom,
                topHalf: topHalf,
                bottomHalf: bottomHalf,
                desiredCount: desiredCount
            )
        }
        
        if result.count > desiredCount {
            result = Array(result.prefix(desiredCount))
        }
        
        #if DEBUG
        logFinalDistribution(result, height: height)
        #endif
        
        Logger.shared.info("Final samples count: \(result.count)")
        return result
    }
    
    private static func partitionCandidates(
        _ candidates: [Candidate],
        height: Int
    ) -> (top: [Candidate], bottom: [Candidate]) {
        
        let topHalf = candidates.filter { $0.y < height / 2 }
        let bottomHalf = candidates.filter { $0.y >= height / 2 }
        
        return (topHalf, bottomHalf)
    }
    
    private struct TargetCounts {
        let top: Int
        let bottom: Int
    }
    
    private static func calculateTargetCounts(
        desiredCount: Int,
        topBottomRatio: Float
    ) -> TargetCounts {
        
        let targetTopCount = Int(Float(desiredCount) * topBottomRatio)
        let targetBottomCount = desiredCount - targetTopCount
        
        return TargetCounts(top: targetTopCount, bottom: targetBottomCount)
    }
    
    private static func selectTopCandidates(
        topHalf: [Candidate],
        bottomHalf: [Candidate],
        targetCounts: TargetCounts
    ) -> (top: [Candidate], bottom: [Candidate]) {
        
        let sortedTop = partialSort(topHalf, count: targetCounts.top)
        let sortedBottom = partialSort(bottomHalf, count: targetCounts.bottom)
        
        return (sortedTop, sortedBottom)
    }
    
    private static func partialSort(
        _ array: [Candidate],
        count: Int
    ) -> [Candidate] {
        
        if array.count <= count {
            return array.sorted { $0.importance > $1.importance }
        }
        
        var arrayCopy = array
        arrayCopy.selectTop(count: count) { $0.importance > $1.importance }
        return Array(arrayCopy.prefix(count))
    }
    
    private static func combineCandidatesIntoSamples(
        sortedTop: [Candidate],
        sortedBottom: [Candidate],
        desiredCount: Int
    ) -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(desiredCount)
        
        for candidate in sortedTop {
            result.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
        }
        
        for candidate in sortedBottom {
            result.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
        }
    
        return result
    }
    
    private static func fillRemainingSlots(
        result: inout [Sample],
        sortedTop: [Candidate],
        sortedBottom: [Candidate],
        topHalf: [Candidate],
        bottomHalf: [Candidate],
        desiredCount: Int
    ) {
        
        let needed = desiredCount - result.count
        
        let selectedCoords = buildSelectedCoordinates(
            sortedTop: sortedTop,
            sortedBottom: sortedBottom
        )
        
        let remainingCandidates = collectRemainingCandidates(
            topHalf: topHalf,
            bottomHalf: bottomHalf,
            selectedCoords: selectedCoords
        )
        
        let sortedRemaining = remainingCandidates.sorted { $0.importance > $1.importance }
        
        addExtraSamples(
            to: &result,
            from: sortedRemaining,
            count: needed
        )
    }
    
    private struct PixelCoord: Hashable {
        let x: Int
        let y: Int
    }
    
    private static func buildSelectedCoordinates(
        sortedTop: [Candidate],
        sortedBottom: [Candidate]
    ) -> Set<PixelCoord> {
        
        let topCoords = Set(sortedTop.map { PixelCoord(x: $0.x, y: $0.y) })
        let bottomCoords = Set(sortedBottom.map { PixelCoord(x: $0.x, y: $0.y) })
        
        return topCoords.union(bottomCoords)
    }
    
    private static func collectRemainingCandidates(
        topHalf: [Candidate],
        bottomHalf: [Candidate],
        selectedCoords: Set<PixelCoord>
    ) -> [Candidate] {
        
        let remainingTop = topHalf.filter { candidate in
            !selectedCoords.contains(PixelCoord(x: candidate.x, y: candidate.y))
        }
        
        let remainingBottom = bottomHalf.filter { candidate in
            !selectedCoords.contains(PixelCoord(x: candidate.x, y: candidate.y))
        }
        
        return remainingTop + remainingBottom
    }
    
    private static func addExtraSamples(
        to result: inout [Sample],
        from sorted: [Candidate],
        count: Int
    ) {
        
        let limit = min(count, sorted.count)
        
        for i in 0..<limit {
            let candidate = sorted[i]
            result.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
        }
    }
    
    // MARK: - Logging
    
    private static func logImportanceMetrics(_ candidates: [Candidate]) {
        let importanceValues = candidates.map { $0.importance }
        
        guard !importanceValues.isEmpty else { return }
    }
    
    #if DEBUG
    private static func logFinalDistribution(_ samples: [Sample], height: Int) { }
    #endif
}

// MARK: - Extensions

private extension SamplingParams {
    var isValid: Bool {
        guard topBottomRatio >= 0.0 && topBottomRatio <= 1.0 else { return false }
        return true
    }
}

private extension Array {
    /// Partial sort selecting top `count` elements according to `areInIncreasingOrder`
    mutating func selectTop(count: Int, by areInIncreasingOrder: (Element, Element) -> Bool) {
        guard count < self.count else {
            self.sort(by: areInIncreasingOrder)
            return
        }
        quickSelect(k: count, by: areInIncreasingOrder)
        self[0..<count].sort(by: areInIncreasingOrder)
    }
    
    private mutating func quickSelect(k: Int, by areInIncreasingOrder: (Element, Element) -> Bool) {
        func partition(low: Int, high: Int) -> Int {
            let pivot = self[high]
            var i = low
            for j in low..<high {
                if areInIncreasingOrder(self[j], pivot) {
                    self.swapAt(i, j)
                    i += 1
                }
            }
            self.swapAt(i, high)
            return i
        }
        
        var low = 0
        var high = self.count - 1
        while low < high {
            let p = partition(low: low, high: high)
            if p == k {
                return
            } else if p < k {
                low = p + 1
            } else {
                high = p - 1
            }
        }
    }
}
