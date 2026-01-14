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
        
        /// Смещение к краям для предотвращения пустых зон
        static let edgeBias: Float = 1.8
        
        /// Порог шума для фильтрации
        static let noiseThreshold: Float = 0.015
        
        /// Расстояние для обнаружения кластеризации
        static let clusteringDistance: Int = 2
        
        /// Отступ от углов для проверки покрытия
        static let cornerMarginRatio: Float = 0.1
        
        /// Усиление яркости для корректировки
        static let brightnessBoost: Float = 1.2
        
        /// Множитель максимальных попыток для случайного выбора
        static let maxAttemptsMultiplier: Int = 15
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
        let cellWidth = Int(imageSize.width) / gridSize
        let cellHeight = Int(imageSize.height) / gridSize
        
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
        
        var clusterCount = 0
        let minClusterSize = 3
        let clusterDistance = Float(Constants.clusteringDistance * 3)
        
        for sample in samples {
            var nearbyCount = 0
            for other in samples {
                let dx = sample.x - other.x
                let dy = sample.y - other.y
                let distance = sqrtf(Float(dx * dx + dy * dy))
                if distance < clusterDistance && distance > 0 {
                    nearbyCount += 1
                }
            }
            if nearbyCount >= minClusterSize { clusterCount += 1 }
        }
        
        return Float(clusterCount) > Float(samples.count) * 0.1
    }
    
    // MARK: - Коррекция
    
    /// Корректирует покрытие изображения
    static func applyCoverageCorrection(samples: [Sample],
                                        cache: PixelCache,
                                        targetCount: Int,
                                        imageSize: CGSize) -> [Sample] {
        var corrected = samples
        
        let gridSize = max(
            1,
            Int(sqrt(Double(cache.width * cache.height) /
                     Double(targetCount * 3)))
        )
        
        for y in stride(from: 0, to: cache.height, by: gridSize) {
            for x in stride(from: 0, to: cache.width, by: gridSize) {
                if corrected.count >= targetCount { break }
                
                // Проверяем, есть ли уже сэмпл в радиусе gridSize
                let alreadyExists = corrected.contains { sample in
                    let dx = Float(x) - Float(sample.x)
                    let dy = Float(y) - Float(sample.y)
                    let distance = sqrtf(dx * dx + dy * dy)
                    return distance < Float(gridSize)
                }
                
                if !alreadyExists {
                    let color = cache.color(atX: x, y: y)
                    if color.w > PixelCacheHelper.Constants.alphaThreshold {
                        corrected.append(Sample(x: x, y: y, color: color))
                    }
                }
            }
        }
        
        return corrected
    }
    
    /// Устраняет кластеризацию сэмплов
    static func applyAntiClustering(samples: [Sample]) -> [Sample] {
        var filtered: [Sample] = []
        var occupiedPositions = Set<String>()
        let gridSize = Constants.clusteringDistance * 2
        
        for sample in samples {
            let gridX = Int(sample.x) / gridSize
            let gridY = Int(sample.y) / gridSize
            let key = "\(gridX)_\(gridY)"
            
            if !occupiedPositions.contains(key) {
                filtered.append(sample)
                occupiedPositions.insert(key)
            }
        }
        return filtered
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
        
        let stepX = max(1, cache.width / max(1, Int(sqrt(Double(targetCount)))))
        let stepY = max(1, cache.height / max(1, Int(sqrt(Double(targetCount)))))
        
        var usedPositions = Set(samples.map { "\($0.x)_\($0.y)" })
        
        // Равномерное заполнение
        outerLoop: for y in stride(from: 0, to: cache.height, by: stepY) {
            for x in stride(from: 0, to: cache.width, by: stepX) {
                if filled.count >= targetCount { break outerLoop }
                
                let key = "\(x)_\(y)"
                if !usedPositions.contains(key) {
                    let color = cache.color(atX: x, y: y)
                    if color.w > PixelCacheHelper.Constants.alphaThreshold {
                        filled.append(Sample(x: x, y: y, color: color))
                        usedPositions.insert(key)
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
                let key = "\(x)_\(y)"
                
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
    
    /// Применяет антикластеризацию для кандидатов
    static func applyAntiClusteringForCandidates(
        candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)]
    ) -> [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] {
        var filtered: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] = []
        var occupiedGrid = Set<String>()
        let gridSize = Constants.clusteringDistance
        
        for candidate in candidates {
            let gridX = candidate.x / gridSize
            let gridY = candidate.y / gridSize
            let key = "\(gridX)_\(gridY)"
            if !occupiedGrid.contains(key) {
                filtered.append(candidate)
                occupiedGrid.insert(key)
            }
        }
        return filtered
    }
    
    /// Вычисляет важность пикселя для семплирования
    static func calculateEnhancedPixelImportance(
        r: Float, g: Float, b: Float, a: Float,
        neighbors: [(r: Float, g: Float, b: Float, a: Float)],
        params: SamplingParams,
        dominantColors: [SIMD3<Float>]
    ) -> Float {
        guard a > PixelCacheHelper.Constants.alphaThreshold else { return 0.0 }
        
        // Локальный контраст
        let localContrast = calculateLocalContrast(
            r: r, g: g, b: b,
            neighbors: neighbors
        )
        
        // Насыщенность
        let saturation = calculateSaturation(r: r, g: g, b: b)
        
        // Уникальность относительно доминирующих цветов
        let uniqueness = calculateUniqueness(
            r: r, g: g, b: b,
            dominantColors: dominantColors
        )
        
        // Взвешивание компонентов
        let contrastWeight = params.contrastWeight * 0.8
        let saturationWeight = params.saturationWeight
        let uniquenessWeight: Float = 0.4
        
        let importance = (contrastWeight * localContrast) +
                         (saturationWeight * saturation) +
                         (uniquenessWeight * uniqueness)
        
        return max(importance, 0.0)
    }
    
    /// Выбирает сэмплы с учетом их важности
    static func selectWeightedSamples(
        from candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)],
        count: Int
    ) -> [Sample] {
        guard count > 0, !candidates.isEmpty else { return [] }
        
        var samples: [Sample] = []
        samples.reserveCapacity(count)
        
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
                    samples.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
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
        
        var attempts = 0
        let maxAttempts = count * Constants.maxAttemptsMultiplier
        
        while samples.count < count && attempts < maxAttempts {
            guard let candidate = candidates.randomElement() else { break }
            samples.append(Sample(x: candidate.x, y: candidate.y, color: candidate.color))
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
}
