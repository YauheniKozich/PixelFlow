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
    
    /// Основной метод семплирования
    static func samplePixels(
        algorithm: SamplingAlgorithm,
        cache: PixelCache,
        targetCount: Int,
        params: SamplingParams,
        dominantColors: [SIMD4<Float>]
    ) throws -> [Sample] {
        
        let samples: [Sample]
        
        switch algorithm {
        case .uniform:
            samples = try enhancedUniformSampling(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                cache: cache,
                dominantColors: dominantColors
            )
            
        case .blueNoise:
            samples = try vibrantBlueNoiseSampling(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                cache: cache,
                dominantColors: dominantColors
            )
            
        case .vanDerCorput:
            samples = try vibrantVanDerCorputSampling(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                cache: cache,
                dominantColors: dominantColors
            )
            
        case .hashBased:
            samples = try vibrantHashSampling(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                cache: cache,
                dominantColors: dominantColors
            )
            
        case .adaptive:
            samples = try vibrantAdaptiveSampling(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                cache: cache,
                dominantColors: dominantColors,
                params: params
            )
        }
        
        return samples
    }
    
    // MARK: - Улучшенное равномерное семплирование
    
    private static func enhancedUniformSampling(
        width: Int,
        height: Int,
        targetCount: Int,
        cache: PixelCache,
        dominantColors: [SIMD4<Float>]
    ) throws -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        let totalPixels = width * height
        let step = max(1, totalPixels / targetCount)
        
        var brightSamples: [Sample] = []
        var pixelIndex = 0
        
        while result.count < targetCount && pixelIndex < totalPixels {
            let x = pixelIndex % width
            let y = pixelIndex / width
            
            let color = cache.color(atX: x, y: y)
            let brightness = calculateBrightness(for: color)
            let saturation = calculateSaturation(for: color)
            
            if brightness > 0.6 && saturation > 0.3 {
                brightSamples.append(Sample(x: x, y: y, color: color))
            }
            
            result.append(Sample(x: x, y: y, color: color))
            pixelIndex += step
        }
        
        // Добавляем яркие пиксели, если есть свободные места
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
        
        return result
    }
    
    // MARK: - Blue-Noise семплирование
    
    private static func vibrantBlueNoiseSampling(
        width: Int,
        height: Int,
        targetCount: Int,
        cache: PixelCache,
        dominantColors: [SIMD4<Float>]
    ) throws -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        // Начальные точки - яркие пиксели
        let seedCount = min(targetCount / 10, 50)
        let seedPoints = findVibrantPixels(
            width: width,
            height: height,
            count: seedCount * 2,
            cache: cache
        ).prefix(seedCount)
        
        for pt in seedPoints {
            result.append(pt)
        }
        
        // Mitchell-Best-Candidate алгоритм
        let candidatesPerPoint = 32
        
        while result.count < targetCount {
            var best: Sample?
            var bestScore: Float = -1
            
            for _ in 0..<candidatesPerPoint {
                let (x, y) = generateBrightCandidate(width: width, height: height, cache: cache)
                
                // Расстояние до уже выбранных точек
                var minDist: Float = .infinity
                for existing in result {
                    let dx = Float(x - existing.x)
                    let dy = Float(y - existing.y)
                    minDist = min(minDist, sqrt(dx*dx + dy*dy))
                }
                
                let col = cache.color(atX: x, y: y)
                let bright = calculateBrightness(for: col)
                let sat = calculateSaturation(for: col)
                
                // Оценка = расстояние * (яркость * насыщенность)
                let score = minDist * (bright * sat * 2.0 + 0.5)
                
                if score > bestScore {
                    bestScore = score
                    best = Sample(x: x, y: y, color: col)
                }
            }
            
            if let cand = best {
                result.append(cand)
            }
        }
        
        return result
    }
    
    // MARK: - Van-der-Corput семплирование
    
    private static func vibrantVanDerCorputSampling(
        width: Int,
        height: Int,
        targetCount: Int,
        cache: PixelCache,
        dominantColors: [SIMD4<Float>]
    ) throws -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        for i in 0..<targetCount {
            let u = vanDerCorput(n: i, base: 2)
            let v = vanDerCorput(n: i, base: 3)
            
            var x = Int(u * Float(width))
            var y = Int(v * Float(height))
            
            x = min(max(x, 0), width - 1)
            y = min(max(y, 0), height - 1)
            
            let col = cache.color(atX: x, y: y)
            let bright = calculateBrightness(for: col)
            let sat = calculateSaturation(for: col)
            
            // Если слишком темный – ищем яркий сосед
            if (bright < 0.3 || sat < 0.2),
               let better = findBrighterNeighbor(x: x, y: y,
                                                width: width, height: height,
                                                cache: cache) {
                result.append(better)
            } else {
                result.append(Sample(x: x, y: y, color: col))
            }
        }
        
        return result
    }
    
    // MARK: - Hash-Based семплирование
    
    private static func vibrantHashSampling(
        width: Int,
        height: Int,
        targetCount: Int,
        cache: PixelCache,
        dominantColors: [SIMD4<Float>]
    ) throws -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        var attempts = 0
        let maxAttempts = targetCount * 3
        
        while result.count < targetCount && attempts < maxAttempts {
            let x = Int(murmurHash3(attempts, seed: 0x9E3779B9)) % width
            let y = Int(murmurHash3(attempts, seed: 0x1B873593)) % height
            
            let col = cache.color(atX: x, y: y)
            let bright = calculateBrightness(for: col)
            let sat = calculateSaturation(for: col)
            
            // Принимаем с вероятностью, пропорциональной яркости + насыщенности
            let prob = bright * 0.7 + sat * 0.3
            if Float.random(in: 0...1) < prob {
                result.append(Sample(x: x, y: y, color: col))
            }
            attempts += 1
        }
        
        // Если не хватает - добавляем самые яркие пиксели
        if result.count < targetCount {
            let need = targetCount - result.count
            let bright = findVibrantPixels(
                width: width,
                height: height,
                count: need * 2,
                cache: cache
            ).prefix(need)
            
            for p in bright where !result.contains(where: { $0.x == p.x && $0.y == p.y }) {
                result.append(p)
            }
        }
        
        return result
    }
    
    // MARK: - Адаптивное семплирование
    
    private static func vibrantAdaptiveSampling(
        width: Int,
        height: Int,
        targetCount: Int,
        cache: PixelCache,
        dominantColors: [SIMD4<Float>],
        params: SamplingParams
    ) throws -> [Sample] {
        
        var result: [Sample] = []
        result.reserveCapacity(targetCount)
        
        // Яркие пиксели (40%)
        let brightTarget = Int(Float(targetCount) * 0.4)
        let brightPool = findVibrantPixels(
            width: width,
            height: height,
            count: brightTarget * 2,
            cache: cache
        )
        
        for pix in brightPool.prefix(brightTarget) {
            result.append(pix)
        }
        
        // Равномерное покрытие (30%)
        let uniformTarget = Int(Float(targetCount) * 0.3)
        let step = max(1, (width * height) / uniformTarget)
        
        for i in stride(from: 0, to: width * height, by: step) where result.count < brightTarget + uniformTarget {
            let x = i % width
            let y = i / width
            let col = cache.color(atX: x, y: y)
            
            // Если уже есть в ярких - пропускаем
            if result.contains(where: { $0.x == x && $0.y == y }) { continue }
            result.append(Sample(x: x, y: y, color: col))
        }
        
        // Пиксели доминирующих цветов (30%)
        let remaining = targetCount - result.count
        if remaining > 0 && !dominantColors.isEmpty {
            let domPixels = findPixelsForDominantColors(
                width: width,
                height: height,
                count: remaining,
                cache: cache,
                dominantColors: dominantColors
            )
            result.append(contentsOf: domPixels)
        }
        
        // Обрезаем, если перебор
        if result.count > targetCount {
            result = Array(result.prefix(targetCount))
        }
        
        return result
    }
    
    // MARK: - Вспомогательные функции
    
    private static func findVibrantPixels(
        width: Int,
        height: Int,
        count: Int,
        cache: PixelCache
    ) -> [Sample] {
        
        var candidates: [(sample: Sample, score: Float)] = []
        let step = max(1, (width * height) / (count * 10))
        
        for i in stride(from: 0, to: width * height, by: step) {
            let x = i % width
            let y = i / width
            let col = cache.color(atX: x, y: y)
            let bright = calculateBrightness(for: col)
            let sat = calculateSaturation(for: col)
            let score = bright * sat
            candidates.append((Sample(x: x, y: y, color: col), score))
        }
        
        candidates.sort { $0.score > $1.score }
        return candidates.prefix(count).map { $0.sample }
    }
    
    private static func generateBrightCandidate(
        width: Int,
        height: Int,
        cache: PixelCache
    ) -> (x: Int, y: Int) {
        
        while true {
            let x = Int.random(in: 0..<width)
            let y = Int.random(in: 0..<height)
            let col = cache.color(atX: x, y: y)
            let bright = calculateBrightness(for: col)
            let sat = calculateSaturation(for: col)
            let prob = bright * 0.6 + sat * 0.4
            if Float.random(in: 0...1) < prob { return (x, y) }
        }
    }
    
    private static func findBrighterNeighbor(
        x: Int, y: Int,
        width: Int, height: Int,
        cache: PixelCache
    ) -> Sample? {
        
        var best: Sample?
        var bestScore: Float = 0
        
        for dy in -1...1 {
            for dx in -1...1 {
                let nx = x + dx
                let ny = y + dy
                guard nx >= 0 && nx < width && ny >= 0 && ny < height else { continue }
                let col = cache.color(atX: nx, y: ny)
                let bright = calculateBrightness(for: col)
                let sat = calculateSaturation(for: col)
                let score = bright * sat
                if score > bestScore {
                    bestScore = score
                    best = Sample(x: nx, y: ny, color: col)
                }
            }
        }
        return bestScore > 0.15 ? best : nil
    }
    
    private static func findPixelsForDominantColors(
        width: Int,
        height: Int,
        count: Int,
        cache: PixelCache,
        dominantColors: [SIMD4<Float>]
    ) -> [Sample] {
        
        var result: [Sample] = []
        
        for dom in dominantColors.prefix(3) {
            if result.count >= count { break }
            
            var best: Sample?
            var bestSim: Float = 0
            let step = max(1, (width * height) / 1000)
            
            for i in stride(from: 0, to: width * height, by: step) {
                let x = i % width
                let y = i / width
                let col = cache.color(atX: x, y: y)
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
    
    private static func calculateBrightness(for color: SIMD4<Float>) -> Float {
        return (color.x + color.y + color.z) / 3.0
    }
    
    private static func calculateSaturation(for color: SIMD4<Float>) -> Float {
        let maxC = max(color.x, max(color.y, color.z))
        let minC = min(color.x, min(color.y, color.z))
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
    
    private static func murmurHash3(_ key: Int, seed: UInt32) -> UInt32 {
        var hash = seed &+ UInt32(key)
        hash &+= hash << 13
        hash ^= hash >> 7
        hash &+= hash << 3
        hash ^= hash >> 17
        hash &+= hash << 5
        return hash
    }
}
