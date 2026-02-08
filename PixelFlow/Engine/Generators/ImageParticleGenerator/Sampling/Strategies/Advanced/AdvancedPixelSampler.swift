//
//  AdvancedSamplingAlgorithms.swift
//  PixelFlow
//
//  Коллекция продвинутых алгоритмов сэмплинга пикселей
//
//  Этот файл содержит различные алгоритмы выбора пикселей из изображения
//  для генерации частиц. Каждый алгоритм имеет свои преимущества и недостатки.
//

import CoreGraphics
import Foundation
import simd

// MARK: - Seedable Random Number Generator

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    
    init(seed: UInt64) {
        self.state = seed == 0 ? 0x123456789abcdef : seed
    }
    
    mutating func next() -> UInt64 {
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 2685821657736338717
    }
}

// MARK: - Sampling Algorithm Types

enum SamplingAlgorithm: Codable {
    case uniform
    case blueNoise
    case vanDerCorput
    case hashBased
    case adaptive
}

// MARK: - Advanced Pixel Sampler

final class AdvancedPixelSampler {
    
    // MARK: - Constants
    
    private enum Constants {
        static let defaultSeed: UInt64 = 42
        static let brightThreshold: Float = 0.6
        static let saturationThreshold: Float = 0.3
        static let lowBrightThreshold: Float = 0.3
        static let lowSatThreshold: Float = 0.2
        static let minScore: Float = 0.15
        static let colorSimilarityThreshold: Float = 0.7
    }
    
    // MARK: - Pixel Caches
    
    /// Структура для хранения предвычисленных данных о пикселях
    private struct PixelCaches {
        let colors: [SIMD4<Float>]
        let brightness: [Float]
        let saturation: [Float]
        let width: Int
        let height: Int
        
        @inline(__always)
        func index(x: Int, y: Int) -> Int {
            y * width + x
        }
        
        var totalPixels: Int {
            width * height
        }
    }
    
    // MARK: - Public Interface
    
    /// Основной метод семплирования
    static func samplePixels(
        algorithm: SamplingAlgorithm,
        cache: PixelCache,
        targetCount: Int,
        params: SamplingParams,
        dominantColors: [SIMD4<Float>],
        seed: UInt64 = Constants.defaultSeed
    ) throws -> [Sample] {
        
        try validateInputs(cache: cache, targetCount: targetCount)
        
        let caches = createCaches(width: cache.width, height: cache.height, cache: cache)
        
        let samples = try generateSamples(
            algorithm: algorithm,
            targetCount: targetCount,
            caches: caches,
            dominantColors: dominantColors,
            params: params,
            seed: seed
        )
        
        try validateOutput(samples: samples)
        
        return samples
    }
    
    // MARK: - Validation
    
    private static func validateInputs(cache: PixelCache, targetCount: Int) throws {
        guard cache.width > 0, cache.height > 0 else {
            throw NSError(
                domain: "AdvancedPixelSampler",
                code: 100,
                userInfo: [NSLocalizedDescriptionKey: "Image dimensions must be positive"]
            )
        }
        
        guard targetCount > 0 else {
            throw NSError(
                domain: "AdvancedPixelSampler",
                code: 101,
                userInfo: [NSLocalizedDescriptionKey: "targetCount must be positive"]
            )
        }
        
        let totalPixels = cache.width * cache.height
        guard targetCount <= totalPixels else {
            throw NSError(
                domain: "AdvancedPixelSampler",
                code: 102,
                userInfo: [NSLocalizedDescriptionKey: "targetCount exceeds total pixels"]
            )
        }
    }
    
    private static func validateOutput(samples: [Sample]) throws {
        guard !samples.isEmpty else {
            throw NSError(
                domain: "AdvancedPixelSampler",
                code: 103,
                userInfo: [NSLocalizedDescriptionKey: "Failed to generate samples"]
            )
        }
    }
    
    // MARK: - Sample Generation
    
    private static func generateSamples(
        algorithm: SamplingAlgorithm,
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>],
        params: SamplingParams,
        seed: UInt64
    ) throws -> [Sample] {
        
        switch algorithm {
        case .uniform:
            return enhancedUniformSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors
            )
            
        case .blueNoise:
            return vibrantBlueNoiseSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors,
                seed: seed
            )
            
        case .vanDerCorput:
            return vibrantVanDerCorputSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors
            )
            
        case .hashBased:
            return vibrantHashSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors,
                seed: seed
            )
            
        case .adaptive:
            return vibrantAdaptiveSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors,
                params: params,
                seed: seed
            )
        }
    }
    
    // MARK: - Cache Creation
    
    /// Создаёт кэши цветов, яркости и насыщенности для всех пикселей
    private static func createCaches(
        width: Int,
        height: Int,
        cache: PixelCache
    ) -> PixelCaches {
        
        let totalPixels = width * height
        
        var colorCache = [SIMD4<Float>]()
        var brightnessCache = [Float]()
        var saturationCache = [Float]()
        
        colorCache.reserveCapacity(totalPixels)
        brightnessCache.reserveCapacity(totalPixels)
        saturationCache.reserveCapacity(totalPixels)
        
        for i in 0..<totalPixels {
            let x = i % width
            let y = i / width
            let color = cache.color(atX: x, y: y)
            
            colorCache.append(color)
            brightnessCache.append(calculateBrightness(for: color))
            saturationCache.append(calculateSaturation(for: color))
        }
        
        return PixelCaches(
            colors: colorCache,
            brightness: brightnessCache,
            saturation: saturationCache,
            width: width,
            height: height
        )
    }
    
    // MARK: - Enhanced Uniform Sampling
    
    private static func enhancedUniformSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>]
    ) -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        let (samples, brightSamples) = generateUniformSamples(
            targetCount: targetCount,
            caches: caches
        )
        
        result = samples
        
        if !brightSamples.isEmpty && result.count < targetCount {
            result = insertBrightSamples(
                into: result,
                brightSamples: brightSamples,
                targetCount: targetCount
            )
        }
        
        #if DEBUG
        logSampleDistribution(result, height: caches.height, method: "Enhanced uniform")
        #endif
        
        return result
    }
    
    private static func generateUniformSamples(
        targetCount: Int,
        caches: PixelCaches
    ) -> (samples: [Sample], brightSamples: [Sample]) {
        
        var samples: [Sample] = []
        var brightSamples: [Sample] = []
        
        let step = Double(caches.totalPixels) / Double(targetCount)
        var currentIndex: Double = 0
        
        while samples.count < targetCount {
            let pixelIndex = Int(currentIndex.rounded())
            guard pixelIndex < caches.totalPixels else { break }
            
            let x = pixelIndex % caches.width
            let y = pixelIndex / caches.width
            
            guard y < caches.height else {
                Logger.shared.warning("Y coordinate \(y) exceeds height \(caches.height)")
                break
            }
            
            let color = caches.colors[pixelIndex]
            let brightness = caches.brightness[pixelIndex]
            let saturation = caches.saturation[pixelIndex]
            let sample = Sample(x: x, y: y, color: color)
            
            if isBrightAndVibrant(brightness: brightness, saturation: saturation) {
                brightSamples.append(sample)
            }
            
            samples.append(sample)
            currentIndex += step
        }
        
        return (samples, brightSamples)
    }
    
    private static func isBrightAndVibrant(brightness: Float, saturation: Float) -> Bool {
        return brightness > Constants.brightThreshold && saturation > Constants.saturationThreshold
    }
    
    private static func insertBrightSamples(
        into samples: [Sample],
        brightSamples: [Sample],
        targetCount: Int
    ) -> [Sample] {
        
        var result = samples
        let needed = targetCount - samples.count
        let toAdd = min(needed, brightSamples.count)
        
        for i in 0..<toAdd {
            let insertIdx = i * result.count / (toAdd + 1)
            if insertIdx < result.count {
                result.insert(brightSamples[i], at: insertIdx)
            }
        }
        
        if result.count > targetCount {
            result = Array(result.prefix(targetCount))
        }
        
        return result
    }
    
    // MARK: - Blue-Noise Sampling
    
    private static func vibrantBlueNoiseSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>],
        seed: UInt64
    ) -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        var rng = SeededGenerator(seed: seed)
        
        let seedPoints = generateSeedPoints(targetCount: targetCount, caches: caches)
        result.append(contentsOf: seedPoints)
        
        let grid = createSpatialGrid(from: result, caches: caches, targetCount: targetCount)
        
        fillWithBlueNoise(
            samples: &result,
            grid: grid,
            targetCount: targetCount,
            caches: caches,
            rng: &rng
        )
        
        return result
    }
    
    private static func generateSeedPoints(targetCount: Int, caches: PixelCaches) -> [Sample] {
        let seedCount = min(targetCount / 10, 50)
        return Array(
            findVibrantPixels(count: seedCount * 2, caches: caches).prefix(seedCount)
        )
    }
    
    private struct SpatialGrid {
        let grid: [[[Sample]]]
        let gridSize: Int
        let gridWidth: Int
        let gridHeight: Int
        
        func gridCoordinates(x: Int, y: Int) -> (gx: Int, gy: Int) {
            return (
                min(x / gridSize, gridWidth - 1),
                min(y / gridSize, gridHeight - 1)
            )
        }
    }
    
    private static func createSpatialGrid(
        from samples: [Sample],
        caches: PixelCaches,
        targetCount: Int
    ) -> SpatialGrid {
        
        let gridSize = max(1, Int(sqrt(Double(caches.totalPixels) / Double(targetCount))))
        let gridW = (caches.width + gridSize - 1) / gridSize
        let gridH = (caches.height + gridSize - 1) / gridSize
        
        // Создаём трёхмерный массив: [gridW][gridH][samples]
        var grid: [[[Sample]]] = Array(
            repeating: Array(repeating: [Sample](), count: gridH),
            count: gridW
        )
        
        let spatialGrid = SpatialGrid(
            grid: grid,
            gridSize: gridSize,
            gridWidth: gridW,
            gridHeight: gridH
        )
        
        for sample in samples {
            let (gx, gy) = spatialGrid.gridCoordinates(x: sample.x, y: sample.y)
            grid[gx][gy].append(sample)
        }
        
        return SpatialGrid(
            grid: grid,
            gridSize: gridSize,
            gridWidth: gridW,
            gridHeight: gridH
        )
    }
    
    private static func fillWithBlueNoise(
        samples: inout [Sample],
        grid: SpatialGrid,
        targetCount: Int,
        caches: PixelCaches,
        rng: inout SeededGenerator
    ) {
        
        var mutableGrid = grid.grid
        let candidatesPerPoint = 32
        
        while samples.count < targetCount {
            guard let bestCandidate = findBestBlueNoiseCandidate(
                grid: mutableGrid,
                spatialGrid: grid,
                caches: caches,
                candidatesPerPoint: candidatesPerPoint,
                rng: &rng
            ) else {
                break
            }
            
            samples.append(bestCandidate)
            let (gx, gy) = grid.gridCoordinates(x: bestCandidate.x, y: bestCandidate.y)
            mutableGrid[gx][gy].append(bestCandidate)
        }
    }
    
    private static func findBestBlueNoiseCandidate(
        grid: [[[Sample]]],
        spatialGrid: SpatialGrid,
        caches: PixelCaches,
        candidatesPerPoint: Int,
        rng: inout SeededGenerator
    ) -> Sample? {
        
        var best: Sample?
        var bestScore: Float = -1
        
        for _ in 0..<candidatesPerPoint {
            let (x, y) = generateBrightCandidate(caches: caches, rng: &rng)
            
            let minDist = calculateMinDistance(
                x: x,
                y: y,
                grid: grid,
                spatialGrid: spatialGrid
            )
            
            let idx = caches.index(x: x, y: y)
            let score = calculateBlueNoiseScore(
                minDist: minDist,
                brightness: caches.brightness[idx],
                saturation: caches.saturation[idx]
            )
            
            if score > bestScore {
                bestScore = score
                best = Sample(x: x, y: y, color: caches.colors[idx])
            }
        }
        
        return best
    }
    
    private static func calculateMinDistance(
        x: Int,
        y: Int,
        grid: [[[Sample]]],
        spatialGrid: SpatialGrid
    ) -> Float {
        
        let (gx, gy) = spatialGrid.gridCoordinates(x: x, y: y)
        var minDist: Float = .infinity
        
        for dx in -1...1 {
            for dy in -1...1 {
                let ngx = gx + dx
                let ngy = gy + dy
                
                guard ngx >= 0 && ngx < spatialGrid.gridWidth &&
                      ngy >= 0 && ngy < spatialGrid.gridHeight else {
                    continue
                }
                
                for existing in grid[ngx][ngy] {
                    let dist = distance(from: (x, y), to: (existing.x, existing.y))
                    minDist = min(minDist, dist)
                }
            }
        }
        
        return minDist
    }
    
    private static func calculateBlueNoiseScore(
        minDist: Float,
        brightness: Float,
        saturation: Float
    ) -> Float {
        return minDist * (brightness * saturation * 2.0 + 0.5)
    }
    
    // MARK: - Van der Corput Sampling
    
    private static func vibrantVanDerCorputSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>]
    ) -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        for i in 0..<targetCount {
            let (x, y) = calculateVanDerCorputCoordinates(index: i, caches: caches)
            let sample = createSampleWithFallback(x: x, y: y, caches: caches)
            result.append(sample)
        }
        
        return result
    }
    
    private static func calculateVanDerCorputCoordinates(
        index: Int,
        caches: PixelCaches
    ) -> (x: Int, y: Int) {
        
        let u = vanDerCorput(n: index, base: 2)
        let v = vanDerCorput(n: index, base: 3)
        
        let x = clamp(Int(u * Float(caches.width)), min: 0, max: caches.width - 1)
        let y = clamp(Int(v * Float(caches.height)), min: 0, max: caches.height - 1)
        
        return (x, y)
    }
    
    private static func createSampleWithFallback(
        x: Int,
        y: Int,
        caches: PixelCaches
    ) -> Sample {
        
        let idx = caches.index(x: x, y: y)
        let brightness = caches.brightness[idx]
        let saturation = caches.saturation[idx]
        
        if shouldFindBetterNeighbor(brightness: brightness, saturation: saturation),
           let betterSample = findBrighterNeighbor(x: x, y: y, caches: caches) {
            return betterSample
        }
        
        return Sample(x: x, y: y, color: caches.colors[idx])
    }
    
    private static func shouldFindBetterNeighbor(brightness: Float, saturation: Float) -> Bool {
        return brightness < Constants.lowBrightThreshold || saturation < Constants.lowSatThreshold
    }
    
    // MARK: - Hash-Based Sampling
    
    private static func vibrantHashSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>],
        seed: UInt64
    ) -> [Sample] {
        
        let candidates = buildCandidateList(caches: caches)
        let cumulative = buildCumulativeDistribution(candidates: candidates)
        
        var result = sampleFromDistribution(
            candidates: candidates,
            cumulative: cumulative,
            targetCount: targetCount,
            caches: caches,
            seed: seed
        )
        
        if result.count < targetCount {
            fillWithVibrantPixels(
                samples: &result,
                targetCount: targetCount,
                caches: caches
            )
        }
        
        return result
    }
    
    private struct Candidate {
        let index: Int
        let probability: Float
    }
    
    private static func buildCandidateList(caches: PixelCaches) -> [Candidate] {
        var candidates: [Candidate] = []
        
        for i in 0..<caches.totalPixels {
            let prob = calculateCandidateProbability(
                brightness: caches.brightness[i],
                saturation: caches.saturation[i]
            )
            
            if prob > 0.01 {
                candidates.append(Candidate(index: i, probability: prob))
            }
        }
        
        if candidates.isEmpty {
            for i in 0..<caches.totalPixels {
                candidates.append(Candidate(index: i, probability: 1.0))
            }
        }
        
        return candidates
    }
    
    private static func calculateCandidateProbability(
        brightness: Float,
        saturation: Float
    ) -> Float {
        return brightness * 0.7 + saturation * 0.3
    }
    
    private static func buildCumulativeDistribution(candidates: [Candidate]) -> [Float] {
        let totalProb = candidates.reduce(0) { $0 + $1.probability }
        
        var cumulative = [Float](repeating: 0, count: candidates.count)
        var accumulator: Float = 0
        
        for (i, candidate) in candidates.enumerated() {
            accumulator += candidate.probability / totalProb
            cumulative[i] = accumulator
        }
        
        return cumulative
    }
    
    private static func sampleFromDistribution(
        candidates: [Candidate],
        cumulative: [Float],
        targetCount: Int,
        caches: PixelCaches,
        seed: UInt64
    ) -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        var used = [Bool](repeating: false, count: caches.totalPixels)
        var rng = SeededGenerator(seed: seed)
        
        var attempts = 0
        let maxAttempts = targetCount * 5
        
        while result.count < targetCount && attempts < maxAttempts {
            let selectedIndex = binarySearchCumulative(
                cumulative: cumulative,
                value: Float.random(in: 0..<1, using: &rng)
            )
            
            let pixelIndex = candidates[selectedIndex].index
            
            if !used[pixelIndex] {
                let x = pixelIndex % caches.width
                let y = pixelIndex / caches.width
                result.append(Sample(x: x, y: y, color: caches.colors[pixelIndex]))
                used[pixelIndex] = true
            }
            
            attempts += 1
        }
        
        return result
    }
    
    private static func binarySearchCumulative(cumulative: [Float], value: Float) -> Int {
        var lo = 0
        var hi = cumulative.count - 1
        
        while lo < hi {
            let mid = (lo + hi) / 2
            if value > cumulative[mid] {
                lo = mid + 1
            } else {
                hi = mid
            }
        }
        
        return lo
    }
    
    private static func fillWithVibrantPixels(
        samples: inout [Sample],
        targetCount: Int,
        caches: PixelCaches
    ) {
        
        let needed = targetCount - samples.count
        let vibrantPixels = findVibrantPixels(count: needed * 2, caches: caches)
        
        var used = Set<Int>()
        for sample in samples {
            used.insert(sample.y * caches.width + sample.x)
        }
        
        for pixel in vibrantPixels {
            if samples.count >= targetCount { break }
            
            let key = pixel.y * caches.width + pixel.x
            if !used.contains(key) {
                samples.append(pixel)
                used.insert(key)
            }
        }
    }
    
    // MARK: - Adaptive Sampling
    
    private static func vibrantAdaptiveSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>],
        params: SamplingParams,
        seed: UInt64
    ) -> [Sample] {
        
        let clampedTarget = min(targetCount, caches.totalPixels)
        var result: [Sample] = []
        result.reserveCapacity(clampedTarget)
        
        var used = [Bool](repeating: false, count: caches.totalPixels)
        var rng = SeededGenerator(seed: seed)
        
        let distribution = AdaptiveDistribution(
            brightTarget: Int(Float(clampedTarget) * 0.4),
            uniformTarget: Int(Float(clampedTarget) * 0.3),
            clampedTarget: clampedTarget
        )
        
        addBrightSamples(
            to: &result,
            used: &used,
            distribution: distribution,
            caches: caches
        )
        
        addUniformCoverage(
            to: &result,
            used: &used,
            distribution: distribution,
            caches: caches
        )
        
        addDominantColorSamples(
            to: &result,
            used: &used,
            targetCount: clampedTarget,
            dominantColors: dominantColors,
            caches: caches
        )
        
        fillRemainingWithRandom(
            samples: &result,
            used: &used,
            targetCount: clampedTarget,
            caches: caches,
            rng: &rng
        )
        
        if result.count != clampedTarget {
            Logger.shared.warning("Adaptive sampling incomplete: \(result.count)/\(clampedTarget)")
        }
        
        return result
    }
    
    private struct AdaptiveDistribution {
        let brightTarget: Int
        let uniformTarget: Int
        let clampedTarget: Int
    }
    
    private static func addBrightSamples(
        to samples: inout [Sample],
        used: inout [Bool],
        distribution: AdaptiveDistribution,
        caches: PixelCaches
    ) {
        guard distribution.brightTarget > 0 else { return }
        
        let brightPixels = findVibrantPixels(
            count: distribution.brightTarget * 2,
            caches: caches
        )
        
        for pixel in brightPixels {
            if samples.count >= distribution.brightTarget { break }
            tryAppendSample(pixel, to: &samples, used: &used, caches: caches)
        }
    }
    
    private static func addUniformCoverage(
        to samples: inout [Sample],
        used: inout [Bool],
        distribution: AdaptiveDistribution,
        caches: PixelCaches
    ) {
        guard distribution.uniformTarget > 0 else { return }
        
        let step = Double(caches.totalPixels) / Double(distribution.uniformTarget)
        var currentIndex: Double = 0
        let targetCount = distribution.brightTarget + distribution.uniformTarget
        
        while Int(currentIndex.rounded()) < caches.totalPixels && samples.count < targetCount {
            let idx = Int(currentIndex.rounded())
            let x = idx % caches.width
            let y = idx / caches.width
            
            tryAppendSample(x: x, y: y, to: &samples, used: &used, caches: caches)
            currentIndex += step
        }
    }
    
    private static func addDominantColorSamples(
        to samples: inout [Sample],
        used: inout [Bool],
        targetCount: Int,
        dominantColors: [SIMD4<Float>],
        caches: PixelCaches
    ) {
        let remaining = targetCount - samples.count
        guard remaining > 0, !dominantColors.isEmpty else { return }
        
        let colorPixels = findPixelsForDominantColors(
            count: remaining,
            caches: caches,
            dominantColors: dominantColors
        )
        
        for pixel in colorPixels {
            if samples.count >= targetCount { break }
            tryAppendSample(pixel, to: &samples, used: &used, caches: caches)
        }
    }
    
    private static func fillRemainingWithRandom(
        samples: inout [Sample],
        used: inout [Bool],
        targetCount: Int,
        caches: PixelCaches,
        rng: inout SeededGenerator
    ) {
        var attempts = 0
        let maxAttempts = caches.totalPixels * 2
        
        while samples.count < targetCount && attempts < maxAttempts {
            let x = Int.random(in: 0..<caches.width, using: &rng)
            let y = Int.random(in: 0..<caches.height, using: &rng)
            tryAppendSample(x: x, y: y, to: &samples, used: &used, caches: caches)
            attempts += 1
        }
    }
    
    private static func tryAppendSample(
        x: Int,
        y: Int,
        to samples: inout [Sample],
        used: inout [Bool],
        caches: PixelCaches
    ) {
        let idx = caches.index(x: x, y: y)
        guard !used[idx] else { return }
        
        samples.append(Sample(x: x, y: y, color: caches.colors[idx]))
        used[idx] = true
    }
    
    private static func tryAppendSample(
        _ sample: Sample,
        to samples: inout [Sample],
        used: inout [Bool],
        caches: PixelCaches
    ) {
        tryAppendSample(x: sample.x, y: sample.y, to: &samples, used: &used, caches: caches)
    }
    
    // MARK: - Helper Functions
    
    private static func findVibrantPixels(
        count: Int,
        caches: PixelCaches
    ) -> [Sample] {
        
        var candidates: [(sample: Sample, score: Float)] = []
        let step = max(1, caches.totalPixels / (count * 10))
        
        for i in stride(from: 0, to: caches.totalPixels, by: step) {
            let x = i % caches.width
            let y = i / caches.width
            let score = caches.brightness[i] * caches.saturation[i]
            
            candidates.append((
                Sample(x: x, y: y, color: caches.colors[i]),
                score
            ))
        }
        
        candidates.sort { $0.score > $1.score }
        return candidates.prefix(count).map { $0.sample }
    }
    
    private static func generateBrightCandidate(
        caches: PixelCaches,
        rng: inout SeededGenerator
    ) -> (x: Int, y: Int) {
        
        let maxTries = 100
        
        for _ in 0..<maxTries {
            let x = Int.random(in: 0..<caches.width, using: &rng)
            let y = Int.random(in: 0..<caches.height, using: &rng)
            let idx = caches.index(x: x, y: y)
            
            let probability = calculateBrightnessProbability(
                brightness: caches.brightness[idx],
                saturation: caches.saturation[idx]
            )
            
            if Float.random(in: 0...1, using: &rng) < probability {
                return (x, y)
            }
        }
        
        return (
            Int.random(in: 0..<caches.width, using: &rng),
            Int.random(in: 0..<caches.height, using: &rng)
        )
    }
    
    private static func calculateBrightnessProbability(
        brightness: Float,
        saturation: Float
    ) -> Float {
        return brightness * 0.6 + saturation * 0.4
    }
    
    private static func findBrighterNeighbor(
        x: Int,
        y: Int,
        caches: PixelCaches
    ) -> Sample? {
        
        var best: Sample?
        var bestScore: Float = 0
        
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x + dx
                let ny = y + dy
                
                guard nx >= 0 && nx < caches.width && ny >= 0 && ny < caches.height else {
                    continue
                }
                
                let idx = caches.index(x: nx, y: ny)
                let score = caches.brightness[idx] * caches.saturation[idx]
                
                if score > bestScore {
                    bestScore = score
                    best = Sample(x: nx, y: ny, color: caches.colors[idx])
                }
            }
        }
        
        return bestScore > Constants.minScore ? best : nil
    }
    
    private static func findPixelsForDominantColors(
        count: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>]
    ) -> [Sample] {
        
        var result: [Sample] = []
        let step = max(1, caches.totalPixels / 1000)
        
        for dominantColor in dominantColors.prefix(3) {
            if result.count >= count { break }
            
            if let bestMatch = findBestColorMatch(
                for: dominantColor,
                caches: caches,
                step: step
            ) {
                result.append(bestMatch)
            }
        }
        
        return result
    }
    
    private static func findBestColorMatch(
        for targetColor: SIMD4<Float>,
        caches: PixelCaches,
        step: Int
    ) -> Sample? {
        
        var best: Sample?
        var bestSimilarity: Float = 0
        
        for i in stride(from: 0, to: caches.totalPixels, by: step) {
            let x = i % caches.width
            let y = i / caches.width
            let color = caches.colors[i]
            let similarity = colorSimilarity(color1: targetColor, color2: color)
            
            if similarity > bestSimilarity {
                bestSimilarity = similarity
                best = Sample(x: x, y: y, color: color)
            }
        }
        
        return bestSimilarity > Constants.colorSimilarityThreshold ? best : nil
    }
    
    // MARK: - Utility Functions
    
    private static func calculateBrightness(for color: SIMD4<Float>) -> Float {
        let alpha = color.w
        
        if alpha >= 1.0 {
            return (color.x + color.y + color.z) / 3.0
        } else if alpha > 0 {
            let unpremultiplied = SIMD3<Float>(
                color.x / alpha,
                color.y / alpha,
                color.z / alpha
            )
            return (unpremultiplied.x + unpremultiplied.y + unpremultiplied.z) / 3.0
        } else {
            return 0
        }
    }

    private static func calculateSaturation(for color: SIMD4<Float>) -> Float {
        let alpha = color.w
        
        let (maxC, minC): (Float, Float)
        
        if alpha >= 1.0 {
            maxC = max(color.x, max(color.y, color.z))
            minC = min(color.x, min(color.y, color.z))
        } else if alpha > 0 {
            let unpremultiplied = SIMD3<Float>(
                color.x / alpha,
                color.y / alpha,
                color.z / alpha
            )
            maxC = max(unpremultiplied.x, max(unpremultiplied.y, unpremultiplied.z))
            minC = min(unpremultiplied.x, min(unpremultiplied.y, unpremultiplied.z))
        } else {
            return 0
        }
        
        guard maxC != 0 else { return 0 }
        return (maxC - minC) / maxC
    }
    
    private static func colorSimilarity(color1: SIMD4<Float>, color2: SIMD4<Float>) -> Float {
        let distance = simd_length(color1 - color2)
        return 1.0 / (1.0 + distance * 2.0)
    }
    
    private static func vanDerCorput(n: Int, base: Int) -> Float {
        var result: Float = 0
        var denominator: Float = 1
        var n = n
        
        while n > 0 {
            denominator *= Float(base)
            result += Float(n % base) / denominator
            n /= base
        }
        
        return result
    }
    
    private static func distance(from p1: (Int, Int), to p2: (Int, Int)) -> Float {
        let dx = Float(p1.0 - p2.0)
        let dy = Float(p1.1 - p2.1)
        return sqrt(dx * dx + dy * dy)
    }
    
    private static func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
        return Swift.min(Swift.max(value, minValue), maxValue)
    }
    
    // MARK: - Debug Logging
    
    #if DEBUG
    private static func logSampleDistribution(
        _ samples: [Sample],
        height: Int,
        method: String
    ) {
        let topCount = samples.filter { $0.y < height / 2 }.count
        let bottomCount = samples.count - topCount
        Logger.shared.debug("\(method): Top \(topCount), Bottom \(bottomCount)")
    }
    #endif
}
