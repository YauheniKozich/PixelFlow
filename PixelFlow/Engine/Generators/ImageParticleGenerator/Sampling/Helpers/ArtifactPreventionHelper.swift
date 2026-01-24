//
//  ArtifactPreventionHelper.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics
import simd

/// Вспомогательный класс для предотвращения артефактов при семплировании
enum ArtifactPreventionHelper {

    // MARK: - Константы
    
    struct Constants {
        /// Минимальное покрытие изображения сэмплами (0-1)
        static let minCoverageRatio: Float = 0.85

        /// Расстояние для обнаружения кластеризации
        static let clusteringDistance: Int = 2

        /// Отступ от углов для проверки покрытия
        static let cornerMarginRatio: Float = 0.1

        /// Множитель максимальных попыток для случайного выбора
        static let maxAttemptsMultiplier: Int = 15

        /// Порог шума для фильтрации незначительных пикселей
        static let noiseThreshold: Float = 0.05
    }
    
    // MARK: - Публичные методы
    
    /// Проверяет и корректирует сэмплы для предотвращения артефактов
    static func validateAndCorrectSamples(samples: [Sample],
                                          cache: PixelCache,
                                          targetCount: Int,
                                          imageSize: CGSize) -> [Sample] {
        var correctedSamples = samples
        
        // Проверяем покрытие изображения
        if !validateCoverage(samples: correctedSamples, imageSize: imageSize) {
            correctedSamples = applyCoverageCorrection(samples: correctedSamples,
                                                       cache: cache,
                                                       targetCount: targetCount,
                                                       imageSize: imageSize)
        }
        
        // Проверяем кластеризацию сэмплов
        if hasClustering(samples: correctedSamples) {
            correctedSamples = applyAntiClustering(samples: correctedSamples)
        }
        
        // Проверяем покрытие углов
        if !validateCornerCoverage(samples: correctedSamples,
                                   imageSize: imageSize) {
            correctedSamples = applyCornerCorrection(samples: correctedSamples,
                                                    cache: cache,
                                                    targetCount: targetCount,
                                                    imageSize: imageSize)
        }
        
        // Корректируем количество сэмплов
        if correctedSamples.count > targetCount {
            correctedSamples = Array(correctedSamples.prefix(targetCount))
        } else if correctedSamples.count < targetCount {
            correctedSamples = fillToRequiredCount(samples: correctedSamples,
                                                   cache: cache,
                                                   targetCount: targetCount)
        }
        
        return correctedSamples
    }
    
    // MARK: - Валидация
    
    /// Проверяет равномерность покрытия изображения сэмплами
    static func validateCoverage(samples: [Sample],
                                 imageSize: CGSize) -> Bool {
        guard !samples.isEmpty,
              imageSize.width > 0,
              imageSize.height > 0 else { return false }
        
        let gridSize = 4
        let cellWidth = max(1, Int(imageSize.width) / gridSize)
        let cellHeight = max(1, Int(imageSize.height) / gridSize)
        
        var coverageGrid = Array(repeating: Array(repeating: false,
                                                  count: gridSize),
                                 count: gridSize)
        
        for sample in samples {
            let cellX = min(gridSize - 1, Int(sample.x) / cellWidth)
            let cellY = min(gridSize - 1, Int(sample.y) / cellHeight)
            coverageGrid[cellY][cellX] = true
        }
        
        let coveredCells = coverageGrid.flatMap { $0 }.filter { $0 }.count
        let coverageRatio = Float(coveredCells) / Float(gridSize * gridSize)
        
        return coverageRatio >= Constants.minCoverageRatio
    }
    
    /// Проверяет покрытие углов изображения
    static func validateCornerCoverage(samples: [Sample],
                                       imageSize: CGSize) -> Bool {
        guard !samples.isEmpty else { return false }
        
        let marginX = max(1,
                         Int(imageSize.width * CGFloat(Constants.cornerMarginRatio)))
        let marginY = max(1,
                         Int(imageSize.height * CGFloat(Constants.cornerMarginRatio)))
        
        var cornersCovered = [false, false, false, false]
        
        for sample in samples {
            let x = Int(sample.x)
            let y = Int(sample.y)
            
            // Левый верхний угол
            if x < marginX && y < marginY { cornersCovered[0] = true }
            // Правый верхний угол
            if x >= Int(imageSize.width) - marginX && y < marginY { cornersCovered[1] = true }
            // Левый нижний угол
            if x < marginX && y >= Int(imageSize.height) - marginY { cornersCovered[2] = true }
            // Правый нижний угол
            if x >= Int(imageSize.width) - marginX &&
               y >= Int(imageSize.height) - marginY { cornersCovered[3] = true }
        }
        
        return cornersCovered.allSatisfy { $0 }
    }
    
    /// Проверяет наличие кластеризации сэмплов
    static func hasClustering(samples: [Sample]) -> Bool {
        guard samples.count > 10 else { return false }

        let cellSize = max(1, Constants.clusteringDistance * 3)
        var grid: [Int: [Sample]] = [:]
        grid.reserveCapacity(samples.count)

        // spatial hash
        for s in samples {
            let gx = Int(s.x) / cellSize
            let gy = Int(s.y) / cellSize
            let key = (gy << 16) | gx
            grid[key, default: []].append(s)
        }

        let minClusterSize = 3
        var clusteredSamples = 0

        for s in samples {
            let gx = Int(s.x) / cellSize
            let gy = Int(s.y) / cellSize

            var neighbors = 0

            // проверяем только 3x3 соседние ячейки
            for ny in (gy - 1)...(gy + 1) {
                for nx in (gx - 1)...(gx + 1) {
                    let key = (ny << 16) | nx
                    guard let bucket = grid[key] else { continue }

                    for other in bucket {
                        if other.x == s.x && other.y == s.y { continue }
                        let dx = Float(s.x - other.x)
                        let dy = Float(s.y - other.y)
                        if dx * dx + dy * dy < Float(cellSize * cellSize) {
                            neighbors += 1
                            if neighbors >= minClusterSize {
                                clusteredSamples += 1
                                break
                            }
                        }
                    }
                }
            }
        }

        return Float(clusteredSamples) > Float(samples.count) * 0.1
    }
    
    // MARK: - Коррекция
    
    /// Корректирует покрытие изображения
    static func applyCoverageCorrection(
        samples: [Sample],
        cache: PixelCache,
        targetCount: Int,
        imageSize: CGSize
    ) -> [Sample] {

        var result = samples
        result.reserveCapacity(targetCount)

        var occupied = Set<Int>()
        occupied.reserveCapacity(result.count)

        for s in result {
            let key = Int(s.y) * cache.width + Int(s.x)
            occupied.insert(key)
        }

        for y in 0..<cache.height {
            for x in 0..<cache.width {

                if result.count >= targetCount {
                    return result
                }

                let key = y * cache.width + x
                if occupied.contains(key) { continue }

                let color = cache.color(atX: x, y: y)
                if color.w > PixelCacheHelper.Constants.alphaThreshold {
                    result.append(Sample(x: x, y: y, color: color))
                    occupied.insert(key)
                }
            }
        }

        return result
    }
    
    /// Устраняет кластеризацию сэмплов через стратифицированную выборку на C
    static func applyAntiClustering(samples: [Sample], bands: Int = 16) -> [Sample] {
        guard !samples.isEmpty else { return [] }

        let imageHeight = samples.map { $0.y }.max() ?? 1
        return stratifiedSample(samples: samples, targetCount: samples.count, imageHeight: imageHeight, bands: bands)
    }

    /// Устраняет кластеризацию кандидатов через стратифицированную выборку
    static func applyAntiClusteringForCandidates(
        candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)]
    ) -> [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] {
        guard !candidates.isEmpty else { return [] }

        // Конвертируем в Sample
        let samples = candidates.map { Sample(x: $0.x, y: $0.y, color: $0.color) }

        // Применяем anti-clustering
        let antiClusteredSamples = applyAntiClustering(samples: samples)

        // Конвертируем обратно, сохраняя importance из оригинала
        return antiClusteredSamples.map { sample in
            if let original = candidates.first(where: { $0.x == sample.x && $0.y == sample.y }) {
                return original
            } else {
                // Не должно случаться, но на всякий случай
                return (x: sample.x, y: sample.y, color: sample.color, importance: 0.1)
            }
        }
    }
    
    /// Добавляет сэмплы в углы изображения
    static func applyCornerCorrection(samples: [Sample],
                                      cache: PixelCache,
                                      targetCount: Int,
                                      imageSize: CGSize) -> [Sample] {
        var corrected = samples
        
        let marginX = max(1,
                         Int(imageSize.width * CGFloat(Constants.cornerMarginRatio)))
        let marginY = max(1,
                         Int(imageSize.height * CGFloat(Constants.cornerMarginRatio)))
        
        let corners = [
            (0, 0),
            (Int(imageSize.width) - marginX, 0),
            (0, Int(imageSize.height) - marginY),
            (Int(imageSize.width) - marginX, Int(imageSize.height) - marginY)
        ]
        
        for (cornerX, cornerY) in corners {
            let hasSample = corrected.contains { sample in
                Int(sample.x) >= cornerX && Int(sample.x) < cornerX + marginX &&
                Int(sample.y) >= cornerY && Int(sample.y) < cornerY + marginY
            }
            
            if !hasSample && corrected.count < targetCount {
                let sampleX = cornerX + marginX / 2
                let sampleY = cornerY + marginY / 2
                let color = cache.color(atX: sampleX, y: sampleY)
                if color.w > PixelCacheHelper.Constants.alphaThreshold {
                    corrected.append(Sample(x: sampleX, y: sampleY, color: color))
                }
            }
        }
        
        return corrected
    }
    
    /// Дополняет сэмплы до требуемого количества
    static func fillToRequiredCount(samples: [Sample],
                                    cache: PixelCache,
                                    targetCount: Int) -> [Sample] {
        var filled = samples
        let needed = targetCount - samples.count
        guard needed > 0 else { return samples }
        
        let grid = max(1, Int(sqrt(Double(targetCount))))
        let stepX = max(1, cache.width / grid)
        let stepY = max(1, cache.height / grid)
        
        var usedPositions = Set(samples.map { ($0.y << 16) | $0.x })
        
        // Равномерное заполнение
        outerLoop: for y in stride(from: 0, to: cache.height, by: stepY) {
            for x in stride(from: 0, to: cache.width, by: stepX) {
                if filled.count >= targetCount { break outerLoop }
                let key = (y << 16) | x
                if !usedPositions.contains(key) {
                    let color = cache.color(atX: x, y: y)
                    if color.w > PixelCacheHelper.Constants.alphaThreshold {
                        filled.append(Sample(x: x, y: y, color: color))
                        usedPositions.insert(key)
                    }
                }
            }
        }

        // Плотный вертикальный проход по всей высоте (sweep), если не хватило
        if filled.count < targetCount {
            for y in 0..<cache.height {
                for x in stride(from: 0, to: cache.width, by: stepX) {
                    if filled.count >= targetCount { break }
                    let key = (y << 16) | x
                    if !usedPositions.contains(key) {
                        let color = cache.color(atX: x, y: y)
                        if color.w > PixelCacheHelper.Constants.alphaThreshold {
                            filled.append(Sample(x: x, y: y, color: color))
                            usedPositions.insert(key)
                        }
                    }
                }
            }
        }
        
        // Случайное заполнение, если все еще не хватает
        if filled.count < targetCount {
            var attempts = 0
            let maxAttempts = needed * 10
            
            while filled.count < targetCount && attempts < maxAttempts {
                let x = Int.random(in: 0..<cache.width)
                let y = Int.random(in: 0..<cache.height)
                let key = (y << 16) | x
                
                if !usedPositions.contains(key) {
                    let color = cache.color(atX: x, y: y)
                    if color.w > PixelCacheHelper.Constants.alphaThreshold {
                        filled.append(Sample(x: x, y: y, color: color))
                        usedPositions.insert(key)
                    }
                }
                attempts += 1
            }
        }
        
        return filled
    }
    
    // MARK: - Расширенные алгоритмы
    
    
    
    /// Выбирает сэмплы с учетом их важности
    static func selectWeightedSamples(
        from candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)],
        count: Int
    ) -> [Sample] {
        guard count > 0, !candidates.isEmpty else { return [] }
        
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        var used = Set<Int>()
        
        let totalImportance = candidates.reduce(0.0) { $0 + $1.importance }
        
        // Если все кандидаты имеют нулевую важность, выбираем случайно
        guard totalImportance > 0 else {
            return selectRandomSamples(from: candidates, count: count)
        }
        
        for _ in 0..<count {
            var target = Float.random(in: 0..<totalImportance)
            for candidate in candidates {
                target -= candidate.importance
                if target <= 0 {
                    let key = (candidate.y << 16) | candidate.x
                    if !used.contains(key) {
                        samples.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
                        used.insert(key)
                    }
                    break
                }
            }
        }
        return samples
    }
    
    /// Выбирает случайные сэмплы из кандидатов
    static func selectRandomSamples(
        from candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)],
        count: Int
    ) -> [Sample] {
        guard count > 0, !candidates.isEmpty else { return [] }
        
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        var used = Set<Int>()
        
        var attempts = 0
        let maxAttempts = count * Constants.maxAttemptsMultiplier
        
        while samples.count < count && attempts < maxAttempts {
            guard let candidate = candidates.randomElement() else { break }
            let key = (candidate.y << 16) | candidate.x
            if !used.contains(key) {
                samples.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
                used.insert(key)
            }
            attempts += 1
        }
        return samples
    }
    
    // MARK: - Вспомогательные методы
    
    private static func calculateLocalContrast(
        r: Float, g: Float, b: Float,
        neighbors: [(r: Float, g: Float, b: Float, a: Float)]
    ) -> Float {
        guard !neighbors.isEmpty else { return 0.0 }
        
        var sum: Float = 0
        for neighbor in neighbors {
            let dr = r - neighbor.r
            let dg = g - neighbor.g
            let db = b - neighbor.b
            sum += simd_length(SIMD3<Float>(dr, dg, db))
        }
        return sum / Float(neighbors.count)
    }
    
    private static func calculateSaturation(r: Float, g: Float, b: Float) -> Float {
        let average = (r + g + b) / 3.0
        let dr = r - average
        let dg = g - average
        let db = b - average
        return sqrtf(dr * dr + dg * dg + db * db)
    }
    
    private static func calculateUniqueness(
        r: Float, g: Float, b: Float,
        dominantColors: [SIMD3<Float>]
    ) -> Float {
        guard !dominantColors.isEmpty else { return 1.0 }

        var minDistance = Float.greatestFiniteMagnitude
        let currentColor = SIMD3<Float>(r, g, b)

        for dominantColor in dominantColors {
            let distance = simd_distance(currentColor, dominantColor)
            if distance < minDistance { minDistance = distance }
            if minDistance < 0.001 { break }
        }

        return min(minDistance, 1.0)
    }

    /// Расчет расширенной важности пикселя на основе контраста, насыщенности и уникальности
    static func calculateEnhancedPixelImportance(
        r: Float, g: Float, b: Float, a: Float,
        neighbors: [(r: Float, g: Float, b: Float, a: Float)],
        params: SamplingParams,
        dominantColors: [SIMD3<Float>]
    ) -> Float {
        // Корректировка для premultiplied alpha: unpremultiply для анализа
        let r_unpremult = a > 0 ? r / a : 0
        let g_unpremult = a > 0 ? g / a : 0
        let b_unpremult = a > 0 ? b / a : 0

        // Также unpremultiply neighbors
        let neighborsUnpremult = neighbors.map { n in
            let na = n.a
            return (r: na > 0 ? n.r / na : 0,
                    g: na > 0 ? n.g / na : 0,
                    b: na > 0 ? n.b / na : 0,
                    a: na)
        }

        let brightness = (r_unpremult + g_unpremult + b_unpremult) / 3.0
        let contrast = calculateLocalContrast(r: r_unpremult, g: g_unpremult, b: b_unpremult, neighbors: neighborsUnpremult)
        let saturation = calculateSaturation(r: r_unpremult, g: g_unpremult, b: b_unpremult)
        let uniqueness = calculateUniqueness(r: r_unpremult, g: g_unpremult, b: b_unpremult, dominantColors: dominantColors)

        // Penalty для белого фона: яркие ненасыщенные пиксели получают низкую важность
        let backgroundPenalty = brightness > 0.8 && saturation < 0.2 ? (brightness - 0.8) / 0.2 * (1 - saturation) : 0

        // Комбинируем веса: edge/contrast доминируют, белый фон штрафуется
        var importance = params.contrastWeight * contrast +
                        params.saturationWeight * saturation +
                        0.3 * uniqueness -
                        backgroundPenalty * 2.0

        // Нормализация importance в [0,1]
        let scalingFactor: Float = 3.0  // Уменьшен для лучшего распределения
        importance = max(0.0, min(1.0, importance * scalingFactor))

        return importance
    }
}

// Swift-обёртка для C-функции stratifiedSampleC
extension ArtifactPreventionHelper {

    static func stratifiedSample(samples: [Sample],
                                 targetCount: Int,
                                 imageHeight: Int,
                                 bands: Int = 16) -> [Sample] {
        guard !samples.isEmpty else { return [] }

        // Преобразуем Swift Sample -> C SampleC
        var cSamples = samples.map { s in
            SampleC(x: Int32(s.x),
                    y: Int32(s.y),
                    r: s.color.x,
                    g: s.color.y,
                    b: s.color.z,
                    a: s.color.w)
        }

        // Выходной массив SampleC
        var outCSamples = [SampleC](repeating: SampleC(x: 0, y: 0, r: 0, g: 0, b: 0, a: 0),
                                    count: targetCount)

        // Вызов C-функции
        stratifiedSampleC(&cSamples,
                          Int32(cSamples.count),
                          Int32(targetCount),
                          Int32(imageHeight),
                          Int32(bands),
                          &outCSamples)

        // Конвертируем обратно в Swift Sample
        return outCSamples.map { c in
            Sample(x: Int(c.x),
                   y: Int(c.y),
                   color: SIMD4<Float>(c.r, c.g, c.b, c.a))
        }
    }
}

// MARK: - Структура для хранения всех пикселей с важностью
struct PixelData {
    let x: Int
    let y: Int
    let color: SIMD4<Float>
    let importance: Float
}

// MARK: - Сбор всех пикселей из cache
extension ArtifactPreventionHelper {

    static func collectAllPixels(from cache: PixelCache) -> [PixelData] {
        var pixels: [PixelData] = []
        for y in 0..<cache.height {
            for x in 0..<cache.width {
                let color = cache.color(atX: x, y: y)
                if color.w > PixelCacheHelper.Constants.alphaThreshold {
                    let importance = color.w * (color.x + color.y + color.z) / 3.0
                    pixels.append(PixelData(x: x, y: y, color: color, importance: importance))
                }
            }
        }
        return pixels
    }
}

// MARK: - Выбор сэмплов для рендеринга
extension ArtifactPreventionHelper {

    static func selectPixelsForRendering(pixels: [PixelData], targetCount: Int, bands: Int = 16) -> [Sample] {
        guard !pixels.isEmpty else { return [] }

        let imageHeight = pixels.map { $0.y }.max() ?? 1
        let selectedPixelData = stratifiedSample(pixels: pixels, targetCount: targetCount, imageHeight: imageHeight, bands: bands)

        return selectedPixelData.map { p in
            Sample(x: p.x, y: p.y, color: p.color)
        }
    }

    // Stratified sampling для PixelData через C-функцию
    static func stratifiedSample(pixels: [PixelData], targetCount: Int, imageHeight: Int, bands: Int = 16) -> [PixelData] {
        guard !pixels.isEmpty else { return [] }

        var cSamples = pixels.map { p in
            SampleC(x: Int32(p.x),
                    y: Int32(p.y),
                    r: p.color.x,
                    g: p.color.y,
                    b: p.color.z,
                    a: p.color.w)
        }

        var outCSamples = [SampleC](repeating: SampleC(x:0, y:0, r:0, g:0, b:0, a:0), count: targetCount)

        stratifiedSampleC(&cSamples,
                          Int32(cSamples.count),
                          Int32(targetCount),
                          Int32(imageHeight),
                          Int32(bands),
                          &outCSamples)

        // Восстанавливаем PixelData с сохранением оригинальной важности
        return outCSamples.map { c in
            let x = Int(c.x)
            let y = Int(c.y)
            if let original = pixels.first(where: { $0.x == x && $0.y == y }) {
                return original
            } else {
                let color = SIMD4<Float>(c.r, c.g, c.b, c.a)
                let importance = c.a * (c.r + c.g + c.b) / 3.0
                return PixelData(x: x, y: y, color: color, importance: importance)
            }
        }
    }
}
