//
//  PixelSampler.swift
//  PixelFlow
//
//  Компонент для сэмплинга пикселей из изображения
//  - Взвешенный отбор пикселей по важности
//  - Адаптивная плотность в сложных областях
//  - Поддержка разных стратегий сэмплинга

import CoreGraphics
import Foundation
import simd

// -----------------------------------------------------------------------------
// MARK: - DefaultPixelSampler
// -----------------------------------------------------------------------------

final class DefaultPixelSampler: PixelSampler {

    // -------------------------------------------------------------------------
    // MARK: - Configuration & contrast method
    // -------------------------------------------------------------------------
    private let config: ParticleGeneratorConfiguration
    private let defaultContrastMethod: ContrastCalculationMethod = .luma

    enum ContrastCalculationMethod {
        case simpleRGB      // Сумма модулей разностей каналов
        case luma           // Яркость (Rec. 709) – дефолт
        case maxChannel     // Максимальная разница по одному каналу
        case perceptual     // Упрощённая «воспринятая» разница
    }

    // -------------------------------------------------------------------------
    // MARK: - Pixel cache (внутренняя, локальная)

    // -------------------------------------------------------------------------
    // MARK: - Init
    // -------------------------------------------------------------------------
    init(config: ParticleGeneratorConfiguration) {
        self.config = config
    }

    // -------------------------------------------------------------------------
    // MARK: - Public API
    // -------------------------------------------------------------------------
    func samplePixels(from analysis: ImageAnalysis,
                     targetCount: Int,
                     config: ParticleGeneratorConfiguration,
                     image: CGImage) throws -> [Sample] {

        Logger.shared.debug("PixelSampler: Старт – \(targetCount) сэмплов, стратегия: \(config.samplingStrategy)")

        // кешируем изображение (локальная переменная → безопасно)
        let cache = try createPixelCache(from: image)

        // выбираем стратегию
        let samples: [Sample] = try {
            switch config.samplingStrategy {
            case .uniform:
                return try uniformSampling(width: cache.width,
                                           height: cache.height,
                                           targetCount: targetCount,
                                           cache: cache)

            case .importance:
                let params = samplingParams(from: config)
                return try importanceSampling(width: cache.width,
                                              height: cache.height,
                                              targetCount: targetCount,
                                              params: params,
                                              cache: cache)

            case .adaptive:
                let params = samplingParams(from: config)
                return try adaptiveSampling(width: cache.width,
                                            height: cache.height,
                                            targetCount: targetCount,
                                            params: params,
                                              cache: cache)

            case .hybrid:
                let params = samplingParams(from: config)
                return try hybridSampling(width: cache.width,
                                          height: cache.height,
                                          targetCount: targetCount,
                                          params: params,
                                          cache: cache)

            case .advanced(let algorithm):
                return try AdvancedPixelSampler.samplePixels(
                    algorithm: algorithm,
                    image: image,
                    targetCount: targetCount
                )
            }
        }()

        Logger.shared.debug("PixelSampler: Сгенерировано \(samples.count) сэмплов")
        return samples
    }

    // -------------------------------------------------------------------------
    // MARK: - Cache creation (самая важная часть)
    // -------------------------------------------------------------------------
    /// Возвращает `PixelCache` со **реальным** `bytesPerRow`.
    private func createPixelCache(from image: CGImage) throws -> PixelCache {
        return try PixelCache.create(from: image)
    }

    // -------------------------------------------------------------------------
    // MARK: - Helpers for sampling parameters
    // -------------------------------------------------------------------------
    private func samplingParams(from cfg: ParticleGeneratorConfiguration) -> SamplingParams {
        if let p = (cfg as? ParticleGenerationConfig)?.samplingParams {
            return p
        }
        // значения по‑умолчанию
        return SamplingParams(importanceThreshold: 0.3,
                              contrastWeight: 0.6,
                              saturationWeight: 0.4,
                              edgeRadius: 2)
    }

    // -------------------------------------------------------------------------
    // MARK: - Uniform sampling
    // -------------------------------------------------------------------------
    private func uniformSampling(width: Int,
                                 height: Int,
                                 targetCount: Int,
                                 cache: PixelCache) throws -> [Sample] {

        var result: [Sample] = []
        result.reserveCapacity(targetCount)

        // Равномерное распределение по всему изображению
        let totalPixels = width * height
        let step = max(1, totalPixels / targetCount)

        var pixelIndex = 0
        while result.count < targetCount && pixelIndex < totalPixels {
            let x = pixelIndex % width
            let y = pixelIndex / width

            result.append(Sample(x: x,
                                 y: y,
                                 color: cache.color(atX: x, y: y)))
            pixelIndex += step
        }

        // Дозаполняем случайными, если не хватило
        if result.count < targetCount {
            try addRandomSamples(to: &result,
                                 width: width,
                                 height: height,
                                 targetCount: targetCount,
                                 cache: cache)
        }

        Logger.shared.debug("Униформное сэмплирование: сгенерировано \(result.count) сэмплов из \(totalPixels) пикселей (шаг: \(step))")
        return result
    }

    // -------------------------------------------------------------------------
    // MARK: - Importance sampling
    // -------------------------------------------------------------------------
    private func importanceSampling(width: Int,
                                   height: Int,
                                   targetCount: Int,
                                   params: SamplingParams,
                                   cache: PixelCache) throws -> [Sample] {

        var candidates: [(x: Int, y: Int, score: Float)] = []
        let step = max(1, min(width, height) / 200)

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let s = calculatePixelImportance(atX: x,
                                                 y: y,
                                                 params: params,
                                                 cache: cache)
                if s >= params.importanceThreshold {
                    candidates.append((x, y, s))
                }
            }
        }

        candidates.sort { $0.score > $1.score }
        let take = min(targetCount, candidates.count)

        var result: [Sample] = []
        var used = Set<UInt64>()

        for i in 0..<take {
            let p = candidates[i]
            let key = positionKey(p.x, p.y)
            used.insert(key)
            result.append(Sample(x: p.x,
                                 y: p.y,
                                 color: cache.color(atX: p.x, y: p.y)))
        }

        // Если не хватает – заполняем равномерно без дублей
        if result.count < targetCount {
            try addUniformSamplesAvoidingDuplicates(to: &result,
                                                     used: &used,
                                                     width: width,
                                                     height: height,
                                                     targetCount: targetCount,
                                                     cache: cache)
        }
        return result
    }

    // -------------------------------------------------------------------------
    // MARK: - Adaptive sampling
    // -------------------------------------------------------------------------
    private func adaptiveSampling(width: Int,
                                 height: Int,
                                 targetCount: Int,
                                 params: SamplingParams,
                                 cache: PixelCache) throws -> [Sample] {

        // 70 % важных + 30 % равномерных
        let importantCount = Int(Float(targetCount) * 0.7)
        let uniformCount   = targetCount - importantCount

        var result = try importanceSampling(width: width,
                                           height: height,
                                           targetCount: importantCount,
                                           params: params,
                                           cache: cache)

        var used = usedPositions(from: result)

        if result.count < targetCount && uniformCount > 0 {
            try addUniformSamplesAvoidingDuplicates(to: &result,
                                                     used: &used,
                                                     width: width,
                                                     height: height,
                                                     targetCount: targetCount,
                                                     cache: cache)
        }
        return result
    }

    // -------------------------------------------------------------------------
    // MARK: - Hybrid sampling
    // -------------------------------------------------------------------------
    private func hybridSampling(width: Int,
                               height: Int,
                               targetCount: Int,
                               params: SamplingParams,
                               cache: PixelCache) throws -> [Sample] {

        // 40 % очень важных, 40 % средних, 20 % равномерных
        let veryImportantCount = Int(Float(targetCount) * 0.4)
        let middleCount        = Int(Float(targetCount) * 0.4)
        let uniformCount       = targetCount - veryImportantCount - middleCount

        // -------------------------------------------------
        // Очень важные (high threshold)
        // -------------------------------------------------
        let highParams = SamplingParams(
            importanceThreshold: params.importanceThreshold * 1.5,
            contrastWeight:      params.contrastWeight,
            saturationWeight:    params.saturationWeight,
            edgeRadius:          params.edgeRadius
        )
        var result = try importanceSampling(width: width,
                                            height: height,
                                            targetCount: veryImportantCount,
                                            params: highParams,
                                            cache: cache)

        // -------------------------------------------------
        // Средне важные (low threshold)
        // -------------------------------------------------
        if result.count < targetCount {
            let lowParams = SamplingParams(
                importanceThreshold: params.importanceThreshold * 0.5,
                contrastWeight:      params.contrastWeight,
                saturationWeight:    params.saturationWeight,
                edgeRadius:          params.edgeRadius
            )
            var used = usedPositions(from: result)
            try addImportantSamplesAvoidingDuplicates(
                to: &result,
                used: &used,
                width: width,
                height: height,
                targetCount: veryImportantCount + middleCount,
                params: lowParams,
                cache: cache)
        }

        // -------------------------------------------------
        // Заполняем оставшиеся равномерно
        // -------------------------------------------------
        if result.count < targetCount && uniformCount > 0 {
            var used = usedPositions(from: result)
            try addUniformSamplesAvoidingDuplicates(to: &result,
                                                     used: &used,
                                                     width: width,
                                                     height: height,
                                                     targetCount: targetCount,
                                                     cache: cache)
        }
        return result
    }

    // -------------------------------------------------------------------------
    // MARK: - Importance helpers (contrast, saturation, …)
    // -------------------------------------------------------------------------
    private func calculatePixelImportance(atX x: Int,
                                         y: Int,
                                         params: SamplingParams,
                                         cache: PixelCache) -> Float {

        let color = cache.color(atX: x, y: y)

        // локальный контраст
        let contrast = calculateLocalContrast(atX: x,
                                              y: y,
                                              radius: params.edgeRadius,
                                              method: defaultContrastMethod,
                                              cache: cache)

        // насыщенность
        let saturation = calculateSaturation(color)

        // суммируем с весами (весы ≤ 1)
        return params.contrastWeight * contrast + params.saturationWeight * saturation
    }

    private func calculateLocalContrast(atX x: Int,
                                       y: Int,
                                       radius: Int,
                                       method: ContrastCalculationMethod,
                                       cache: PixelCache) -> Float {

        let centre = cache.color(atX: x, y: y)
        let neighbours = getNeighbors(x: x,
                                      y: y,
                                      radius: radius,
                                      width: cache.width,
                                      height: cache.height)

        guard !neighbours.isEmpty else { return 0 }

        var sum: Float = 0
        for n in neighbours {
            let col = cache.color(atX: n.x, y: n.y)
            sum += calculateColorDifference(color1: centre,
                                            color2: col,
                                            method: method)
        }
        return sum / Float(neighbours.count)
    }

    private func calculateColorDifference(color1: SIMD4<Float>,
                                          color2: SIMD4<Float>,
                                          method: ContrastCalculationMethod) -> Float {
        switch method {
        case .simpleRGB:
            return abs(color1.x - color2.x) +
                   abs(color1.y - color2.y) +
                   abs(color1.z - color2.z)

        case .luma:
            let l1 = 0.2126 * color1.x + 0.7152 * color1.y + 0.0722 * color1.z
            let l2 = 0.2126 * color2.x + 0.7152 * color2.y + 0.0722 * color2.z
            return abs(l1 - l2)

        case .maxChannel:
            let r = abs(color1.x - color2.x)
            let g = abs(color1.y - color2.y)
            let b = abs(color1.z - color2.z)
            return max(r, g, b)

        case .perceptual:
            // упрощённый perceptual‑метод
            let l1 = 0.299 * color1.x + 0.587 * color1.y + 0.114 * color1.z
            let l2 = 0.299 * color2.x + 0.587 * color2.y + 0.114 * color2.z
            let lDiff = abs(l1 - l2)
            let cDiff = (abs(color1.x - color2.x) +
                         abs(color1.y - color2.y) +
                         abs(color1.z - color2.z)) / 3.0
            return lDiff * 0.7 + cDiff * 0.3
        }
    }

    private func calculateSaturation(_ c: SIMD4<Float>) -> Float {
        let maxC = max(c.x, c.y, c.z)
        let minC = min(c.x, c.y, c.z)
        return maxC > 0 ? (maxC - minC) / maxC : 0
    }

    // -------------------------------------------------------------------------
    // MARK: - Neighbour helpers
    // -------------------------------------------------------------------------
    private func getNeighbors(x: Int,
                              y: Int,
                              radius: Int,
                              width: Int,
                              height: Int) -> [(x: Int, y: Int)] {
        var list: [(Int, Int)] = []
        let r = max(1, radius)

        for dy in -r...r {
            for dx in -r...r {
                if dx == 0 && dy == 0 { continue }
                let nx = x + dx, ny = y + dy
                if nx >= 0 && nx < width && ny >= 0 && ny < height {
                    list.append((nx, ny))
                }
            }
        }
        return list
    }

    // -------------------------------------------------------------------------
    // MARK: - Random / uniform fillers (добавление недостающих точек)
    // -------------------------------------------------------------------------
    private func addRandomSamples(to samples: inout [Sample],
                                 width: Int,
                                 height: Int,
                                 targetCount: Int,
                                 cache: PixelCache) throws {

        var used = usedPositions(from: samples)
        let needed = targetCount - samples.count
        var attempts = 0
        let maxAttempts = needed * 5

        while samples.count < targetCount && attempts < maxAttempts {
            let x = Int.random(in: 0..<width)
            let y = Int.random(in: 0..<height)
            let key = positionKey(x, y)
            if used.insert(key).inserted {
                samples.append(Sample(x: x,
                                     y: y,
                                     color: cache.color(atX: x, y: y)))
            }
            attempts += 1
        }

        if samples.count < targetCount {
            Logger.shared.warning("PixelSampler: не удалось сгенерировать достаточное количество уникальных случайных сэмплов (\(samples.count)/\(targetCount))")
        }
    }

    private func addUniformSamplesAvoidingDuplicates(to samples: inout [Sample],
                                                     used: inout Set<UInt64>,
                                                     width: Int,
                                                     height: Int,
                                                     targetCount: Int,
                                                     cache: PixelCache) throws {

        let needed = targetCount - samples.count
        guard needed > 0 else { return }

        // небольшая сетка – быстрое заполнение без дублей
        let stepX = max(1, width / 100)
        let stepY = max(1, height / 100)

        outer: for y in stride(from: 0, to: height, by: stepY) {
            for x in stride(from: 0, to: width, by: stepX) {
                if samples.count == targetCount { break outer }
                let key = positionKey(x, y)
                if used.insert(key).inserted {
                    samples.append(Sample(x: x,
                                         y: y,
                                         color: cache.color(atX: x, y: y)))
                }
            }
        }

        // Если всё ещё не достаточно – добираем случайными
        if samples.count < targetCount {
            try addRandomSamples(to: &samples,
                                 width: width,
                                 height: height,
                                 targetCount: targetCount,
                                 cache: cache)
        }
    }

    private func addImportantSamplesAvoidingDuplicates(to samples: inout [Sample],
                                                      used: inout Set<UInt64>,
                                                      width: Int,
                                                      height: Int,
                                                      targetCount: Int,
                                                      params: SamplingParams,
                                                      cache: PixelCache) throws {

        let needed = targetCount - samples.count
        guard needed > 0 else { return }

        var candidates: [(x: Int, y: Int, score: Float)] = []
        let step = max(1, min(width, height) / 200)

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let key = positionKey(x, y)
                if used.contains(key) { continue }

                let s = calculatePixelImportance(atX: x,
                                                 y: y,
                                                 params: params,
                                                 cache: cache)
                if s >= params.importanceThreshold {
                    candidates.append((x, y, s))
                }
            }
        }

        candidates.sort { $0.score > $1.score }

        for i in 0..<min(needed, candidates.count) {
            let p = candidates[i]
            let key = positionKey(p.x, p.y)
            used.insert(key)
            samples.append(Sample(x: p.x,
                                 y: p.y,
                                 color: cache.color(atX: p.x, y: p.y)))
        }
    }

    // -------------------------------------------------------------------------
    // MARK: - Utility (ключи, набор уже‑использованных позиций)
    // -------------------------------------------------------------------------
    @inline(__always)
    private func positionKey(_ x: Int, _ y: Int) -> UInt64 {
        // 32‑бит x + 32‑бит y → один 64‑битный ключ
        return (UInt64(x) << 32) | UInt64(y)
    }

    private func usedPositions(from samples: [Sample]) -> Set<UInt64> {
        var set = Set<UInt64>(minimumCapacity: samples.count)
        for s in samples { set.insert(positionKey(s.x, s.y)) }
        return set
    }

    // -------------------------------------------------------------------------
    // MARK: - Deinit (debug only)
    // -------------------------------------------------------------------------
    deinit {
        #if DEBUG
        print("[PixelSampler] deinit")
        #endif
    }
}
