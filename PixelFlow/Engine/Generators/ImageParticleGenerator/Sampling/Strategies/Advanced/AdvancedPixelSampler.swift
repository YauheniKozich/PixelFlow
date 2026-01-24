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
    init(seed: UInt64) { self.state = seed == 0 ? 0x123456789abcdef : seed }
    mutating func next() -> UInt64 {
        var x = state
        x ^= x >> 12
        x ^= x << 25
        x ^= x >> 27
        state = x
        return x &* 2685821657736338717
    }
}

// MARK: - Перечисления и типы

enum SamplingAlgorithm: Codable {
    case uniform
    case blueNoise
    case vanDerCorput
    case hashBased
    case adaptive
}

// MARK: - AdvancedPixelSampler

final class AdvancedPixelSampler {
    
    // MARK: - Типы для кэширования
    
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
    }
    
    /// Основной метод семплирования
    static func samplePixels(
        algorithm: SamplingAlgorithm,
        cache: PixelCache,
        targetCount: Int,
        params: SamplingParams,
        dominantColors: [SIMD4<Float>],
        seed: UInt64 = 42
    ) throws -> [Sample] {
        // Валидация параметров
        guard cache.width > 0, cache.height > 0 else {
            throw NSError(domain: "AdvancedPixelSampler", code: 100,
                         userInfo: [NSLocalizedDescriptionKey: "Image dimensions must be positive"])
        }
        guard targetCount > 0 else {
            throw NSError(domain: "AdvancedPixelSampler", code: 101,
                         userInfo: [NSLocalizedDescriptionKey: "targetCount must be positive"])
        }
        
        let totalPixels = cache.width * cache.height
        guard targetCount <= totalPixels else {
            throw NSError(domain: "AdvancedPixelSampler", code: 102,
                         userInfo: [NSLocalizedDescriptionKey: "targetCount exceeds total pixels"])
        }
        
        // ОПТИМИЗАЦИЯ: Создаем кэши ОДИН РАЗ для всех алгоритмов
        let caches = createCaches(width: cache.width, height: cache.height, cache: cache)
        
        let samples: [Sample]
        switch algorithm {
        case .uniform:
            samples = enhancedUniformSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors
            )
        case .blueNoise:
            samples = vibrantBlueNoiseSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors,
                seed: seed
            )
        case .vanDerCorput:
            samples = vibrantVanDerCorputSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors
            )
        case .hashBased:
            samples = vibrantHashSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors,
                seed: seed
            )
        case .adaptive:
            samples = vibrantAdaptiveSampling(
                targetCount: targetCount,
                caches: caches,
                dominantColors: dominantColors,
                params: params,
                seed: seed
            )
        }
        
        // Проверка результата
        guard !samples.isEmpty else {
            throw NSError(domain: "AdvancedPixelSampler", code: 103,
                         userInfo: [NSLocalizedDescriptionKey: "Failed to generate samples"])
        }
        
        return samples
    }
    
    // MARK: - Кэширование
    
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
    
    // MARK: - Улучшенное равномерное семплирование
    
    private static func enhancedUniformSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>]
    ) -> [Sample] {
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        let totalPixels = caches.width * caches.height
        let step = Double(totalPixels) / Double(targetCount)
        var brightSamples: [Sample] = []
        var currentIndex: Double = 0
        
        while result.count < targetCount {
            let pixelIndex = Int(currentIndex.rounded())
            guard pixelIndex < totalPixels else { break }
            
            let x = pixelIndex % caches.width
            let y = pixelIndex / caches.width
            
            guard y < caches.height else {
                Logger.shared.warning("Y coordinate \(y) exceeds height \(caches.height)")
                break
            }
            
            let color = caches.colors[pixelIndex]
            let brightness = caches.brightness[pixelIndex]
            let saturation = caches.saturation[pixelIndex]
            
            if brightness > 0.6 && saturation > 0.3 {
                brightSamples.append(Sample(x: x, y: y, color: color))
            }
            
            result.append(Sample(x: x, y: y, color: color))
            currentIndex += step
        }
        
        if !brightSamples.isEmpty && result.count < targetCount {
            let needed = targetCount - result.count
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
        }
        
        #if DEBUG
        logSampleDistribution(result, height: caches.height, method: "Enhanced uniform")
        #endif
        
        return result
    }
    
    // MARK: - Blue-Noise семплирование
    
    private static func vibrantBlueNoiseSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>],
        seed: UInt64
    ) -> [Sample] {
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        var rng = SeededGenerator(seed: seed)
        
        // Начальные точки - яркие пиксели
        let seedCount = min(targetCount / 10, 50)
        let seedPoints = findVibrantPixels(
            count: seedCount * 2,
            caches: caches
        ).prefix(seedCount)
        
        for pt in seedPoints {
            result.append(pt)
        }
        
        let gridSize = max(1, Int(sqrt(Double(caches.width * caches.height) / Double(targetCount))))
        let gridW = (caches.width + gridSize - 1) / gridSize
        let gridH = (caches.height + gridSize - 1) / gridSize
        
        var grid = Array(
            repeating: [[Sample]](repeating: [], count: gridH),
            count: gridW
        )
        
        func gridXY(_ x: Int, _ y: Int) -> (gx: Int, gy: Int) {
            return (min(x / gridSize, gridW - 1), min(y / gridSize, gridH - 1))
        }
        
        for pt in result {
            let (gx, gy) = gridXY(pt.x, pt.y)
            grid[gx][gy].append(pt)
        }
        
        let candidatesPerPoint = 32
        while result.count < targetCount {
            var best: Sample?
            var bestScore: Float = -1
            
            for _ in 0..<candidatesPerPoint {
                let (x, y) = generateBrightCandidate(caches: caches, rng: &rng)
                let (gx, gy) = gridXY(x, y)
                var minDist: Float = .infinity
                
                for dx in -1...1 {
                    for dy in -1...1 {
                        let ngx = gx + dx
                        let ngy = gy + dy
                        guard ngx >= 0 && ngx < gridW && ngy >= 0 && ngy < gridH else { continue }
                        
                        for existing in grid[ngx][ngy] {
                            let dx = Float(x - existing.x)
                            let dy = Float(y - existing.y)
                            let dist = sqrt(dx*dx + dy*dy)
                            if dist < minDist {
                                minDist = dist
                            }
                        }
                    }
                }
                
                let idx = caches.index(x: x, y: y)
                let col = caches.colors[idx]
                let bright = caches.brightness[idx]
                let sat = caches.saturation[idx]
                let score = minDist * (bright * sat * 2.0 + 0.5)
                
                if score > bestScore {
                    bestScore = score
                    best = Sample(x: x, y: y, color: col)
                }
            }
            
            if let cand = best {
                result.append(cand)
                let (gx, gy) = gridXY(cand.x, cand.y)
                grid[gx][gy].append(cand)
            }
        }
        
        return result
    }
    
    // MARK: - Van-der-Corput семплирование
    
    private static func vibrantVanDerCorputSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>]
    ) -> [Sample] {
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        for i in 0..<targetCount {
            let u = vanDerCorput(n: i, base: 2)
            let v = vanDerCorput(n: i, base: 3)
            var x = Int(u * Float(caches.width))
            var y = Int(v * Float(caches.height))
            x = min(max(x, 0), caches.width - 1)
            y = min(max(y, 0), caches.height - 1)
            
            let idx = caches.index(x: x, y: y)
            let col = caches.colors[idx]
            let bright = caches.brightness[idx]
            let sat = caches.saturation[idx]
            
            if (bright < 0.3 || sat < 0.2),
               let better = findBrighterNeighbor(x: x, y: y, caches: caches) {
                result.append(better)
            } else {
                result.append(Sample(x: x, y: y, color: col))
            }
        }
        
        return result
    }
    
    // MARK: - Hash-Based семплирование
    
    private static func vibrantHashSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>],
        seed: UInt64
    ) -> [Sample] {
        let totalPixels = caches.width * caches.height
        
        var candidates: [(idx: Int, prob: Float)] = []
        for i in 0..<totalPixels {
            let prob = caches.brightness[i] * 0.7 + caches.saturation[i] * 0.3
            if prob > 0.01 {
                candidates.append((idx: i, prob: prob))
            }
        }
        
        if candidates.isEmpty {
            for i in 0..<totalPixels {
                candidates.append((idx: i, prob: 1.0))
            }
        }
        
        let totalProb = candidates.reduce(0) { $0 + $1.prob }
        var cumulative = [Float](repeating: 0, count: candidates.count)
        var acc: Float = 0
        for (i, c) in candidates.enumerated() {
            acc += c.prob / totalProb
            cumulative[i] = acc
        }
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        var used = [Bool](repeating: false, count: totalPixels)
        var rng = SeededGenerator(seed: seed)
        var attempts = 0
        let maxAttempts = targetCount * 5
        
        while result.count < targetCount && attempts < maxAttempts {
            let r = Float.random(in: 0..<1, using: &rng)
            var lo = 0, hi = cumulative.count - 1
            
            while lo < hi {
                let mid = (lo + hi) / 2
                if r > cumulative[mid] {
                    lo = mid + 1
                } else {
                    hi = mid
                }
            }
            
            let idx = candidates[lo].idx
            if !used[idx] {
                let x = idx % caches.width
                let y = idx / caches.width
                let col = caches.colors[idx]
                result.append(Sample(x: x, y: y, color: col))
                used[idx] = true
            }
            attempts += 1
        }
        
        if result.count < targetCount {
            let need = targetCount - result.count
            let bright = findVibrantPixels(count: need * 2, caches: caches).prefix(need)
            
            for p in bright where !used[p.y * caches.width + p.x] {
                result.append(p)
                used[p.y * caches.width + p.x] = true
                if result.count >= targetCount { break }
            }
        }
        
        return result
    }
    
    // MARK: - Адаптивное семплирование
    
    private static func vibrantAdaptiveSampling(
        targetCount: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>],
        params: SamplingParams,
        seed: UInt64
    ) -> [Sample] {
        let totalPixels = caches.width * caches.height
        let clampedTarget = min(targetCount, totalPixels)
        
        var result: [Sample] = []
        result.reserveCapacity(clampedTarget)
        var used = [Bool](repeating: false, count: totalPixels)
        
        @inline(__always)
        func tryAppend(x: Int, y: Int) {
            let idx = caches.index(x: x, y: y)
            guard !used[idx] else { return }
            let col = caches.colors[idx]
            result.append(Sample(x: x, y: y, color: col))
            used[idx] = true
        }
        
        var rng = SeededGenerator(seed: seed)
        
        // 1. Яркие пиксели — 40%
        let brightTarget = Int(Float(clampedTarget) * 0.4)
        if brightTarget > 0 {
            let bright = findVibrantPixels(count: brightTarget * 2, caches: caches)
            for p in bright {
                if result.count >= brightTarget { break }
                tryAppend(x: p.x, y: p.y)
            }
        }
        
        // 2. Равномерное покрытие — 30%
        let uniformTarget = Int(Float(clampedTarget) * 0.3)
        if uniformTarget > 0 {
            let step = Double(totalPixels) / Double(uniformTarget)
            var i: Double = 0
            while Int(i.rounded()) < totalPixels && result.count < brightTarget + uniformTarget {
                let idx = Int(i.rounded())
                let x = idx % caches.width
                let y = idx / caches.width
                tryAppend(x: x, y: y)
                i += step
            }
        }
        
        // 3. Доминирующие цвета — 30%
        let remainingAfterUniform = clampedTarget - result.count
        if remainingAfterUniform > 0, !dominantColors.isEmpty {
            let dom = findPixelsForDominantColors(
                count: remainingAfterUniform,
                caches: caches,
                dominantColors: dominantColors
            )
            for p in dom {
                if result.count >= clampedTarget { break }
                tryAppend(x: p.x, y: p.y)
            }
        }
        
        // 4. Fallback — добиваем случайными
        var attempts = 0
        let maxAttempts = totalPixels * 2
        while result.count < clampedTarget && attempts < maxAttempts {
            let x = Int.random(in: 0..<caches.width, using: &rng)
            let y = Int.random(in: 0..<caches.height, using: &rng)
            tryAppend(x: x, y: y)
            attempts += 1
        }
        
        if result.count != clampedTarget {
            Logger.shared.warning("Adaptive sampling incomplete: \(result.count)/\(clampedTarget)")
        }
        
        return result
    }
    
    // MARK: - Вспомогательные функции
    
    private static func findVibrantPixels(
        count: Int,
        caches: PixelCaches
    ) -> [Sample] {
        var candidates: [(sample: Sample, score: Float)] = []
        let totalPixels = caches.width * caches.height
        let step = max(1, totalPixels / (count * 10))
        
        for i in stride(from: 0, to: totalPixels, by: step) {
            let x = i % caches.width
            let y = i / caches.width
            let col = caches.colors[i]
            let bright = caches.brightness[i]
            let sat = caches.saturation[i]
            let score = bright * sat
            
            candidates.append((Sample(x: x, y: y, color: col), score))
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
            let bright = caches.brightness[idx]
            let sat = caches.saturation[idx]
            let prob = bright * 0.6 + sat * 0.4
            
            if Float.random(in: 0...1, using: &rng) < prob {
                return (x, y)
            }
        }
        
        // Fallback: случайная точка
        return (
            Int.random(in: 0..<caches.width, using: &rng),
            Int.random(in: 0..<caches.height, using: &rng)
        )
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
                guard nx >= 0 && nx < caches.width && ny >= 0 && ny < caches.height else { continue }
                
                let idx = caches.index(x: nx, y: ny)
                let bright = caches.brightness[idx]
                let sat = caches.saturation[idx]
                let score = bright * sat
                
                if score > bestScore {
                    let col = caches.colors[idx]
                    bestScore = score
                    best = Sample(x: nx, y: ny, color: col)
                }
            }
        }
        
        return bestScore > 0.15 ? best : nil
    }
    
    private static func findPixelsForDominantColors(
        count: Int,
        caches: PixelCaches,
        dominantColors: [SIMD4<Float>]
    ) -> [Sample] {
        var result: [Sample] = []
        let totalPixels = caches.width * caches.height
        
        for dom in dominantColors.prefix(3) {
            if result.count >= count { break }
            var best: Sample?
            var bestSim: Float = 0
            let step = max(1, totalPixels / 1000)
            
            for i in stride(from: 0, to: totalPixels, by: step) {
                let x = i % caches.width
                let y = i / caches.width
                let col = caches.colors[i]
                let sim = colorSimilarity(color1: dom, color2: col)
                
                if sim > bestSim {
                    bestSim = sim
                    best = Sample(x: x, y: y, color: col)
                }
            }
            
            if let p = best, bestSim > 0.7 {
                result.append(p)
            }
        }
        
        return result
    }
    
    // MARK: - Утилиты
    
    private static func calculateBrightness(for color: SIMD4<Float>) -> Float {
        // Корректировка для premultiplied alpha: unpremultiply RGB если alpha < 1
        let alpha = color.w
        if alpha >= 1.0 {
            return (color.x + color.y + color.z) / 3.0
        } else if alpha > 0 {
            let r_unpremult = color.x / alpha
            let g_unpremult = color.y / alpha
            let b_unpremult = color.z / alpha
            return (r_unpremult + g_unpremult + b_unpremult) / 3.0
        } else {
            return 0
        }
    }

    private static func calculateSaturation(for color: SIMD4<Float>) -> Float {
        // Корректировка для premultiplied alpha: unpremultiply RGB если alpha < 1
        let alpha = color.w
        let maxC: Float
        let minC: Float
        if alpha >= 1.0 {
            maxC = max(color.x, max(color.y, color.z))
            minC = min(color.x, min(color.y, color.z))
        } else if alpha > 0 {
            let r_unpremult = color.x / alpha
            let g_unpremult = color.y / alpha
            let b_unpremult = color.z / alpha
            maxC = max(r_unpremult, max(g_unpremult, b_unpremult))
            minC = min(r_unpremult, min(g_unpremult, b_unpremult))
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
    
    #if DEBUG
    private static func logSampleDistribution(_ samples: [Sample], height: Int, method: String) {
        var topCount = 0
        var bottomCount = 0
        
        for sample in samples {
            if sample.y < height / 2 {
                topCount += 1
            } else {
                bottomCount += 1
            }
        }
        
        Logger.shared.debug("\(method): Top \(topCount), Bottom \(bottomCount)")
    }
    #endif
}
