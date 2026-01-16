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
    
    static func sample(
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>] = []
    ) throws -> [Sample] {
        
        // Validate inputs
        guard width > 0, height > 0 else {
            Logger.shared.error("Invalid image dimensions: width and height must be positive")
            return []
        }
        guard targetCount > 0 else { return [] }
        guard params.isValid else {
            Logger.shared.error("Invalid SamplingParams provided")
            return []
        }
        
        Logger.shared.info("Sampling started: width=\(width), height=\(height), targetCount=\(targetCount), params=\(params)")
        
        let totalPixels = width * height
        if targetCount >= totalPixels {
            return try UniformSamplingStrategy.sample(
                width: width,
                height: height,
                targetCount: totalPixels,
                cache: cache
            )
        }
        
        // ИСПРАВЛЕНИЕ: Улучшенный расчет stride
        let maxScanDimension = 512
        let scanStrideX = max(1, min(width / maxScanDimension, width / 16))
        let scanStrideY = max(1, min(height / maxScanDimension, height / 16))
        
        Logger.shared.debug("Сканирование изображения \(width)x\(height) с шагом \(scanStrideX)x\(scanStrideY)")
        
        // Color cache уже в правильном формате SIMD3<Float>
        let colorCache = dominantColors
        
        // Сбор важных пикселей
        var candidates = gatherImportantPixels(
            cache: cache,
            width: width,
            height: height,
            strideX: scanStrideX,
            strideY: scanStrideY,
            params: params,
            dominantColors: colorCache
        )

        // Логирование метрик importance для калибровки шкалы
        let importanceValues = candidates.map { $0.importance }
        if !importanceValues.isEmpty {
            let minImp = importanceValues.min() ?? 0
            let maxImp = importanceValues.max() ?? 0
            let meanImp = importanceValues.reduce(0, +) / Float(importanceValues.count)
            Logger.shared.debug("Importance metrics: min=\(String(format: "%.3f", minImp)), max=\(String(format: "%.3f", maxImp)), mean=\(String(format: "%.3f", meanImp)), count=\(importanceValues.count)")
        }
        
        Logger.shared.debug("Найдено \(candidates.count) важных пикселей")
        
        // Если недостаточно кандидатов - добавляем резервные
        let minImportant = max(targetCount / 4, 10)
        if candidates.count < minImportant {
            Logger.shared.warning("Недостаточно важных пикселей (\(candidates.count)), добавляем fallback")
            let needed = targetCount - candidates.count
            let fallback = gatherFallbackPixels(
                cache: cache,
                width: width,
                height: height,
                neededCount: needed
            )
            candidates.append(contentsOf: fallback)
        }
        
        // Если все еще мало - берем все
        if candidates.count <= targetCount {
            let samples = candidates.map { Sample(x: $0.x, y: $0.y, color: $0.color) }
            Logger.shared.info("Возврат \(samples.count) сэмплов (все найденные)")
            return samples
        }
        
        // Балансируем И сортируем по вертикали
        let finalSamples = selectBalancedSamples(
            candidates: candidates,
            desiredCount: targetCount,
            height: height,
            topBottomRatio: params.topBottomRatio
        )
        
        Logger.shared.info("Возврат \(finalSamples.count) окончательных сэмплов")
        return finalSamples
    }
    
    // MARK: - ИСПРАВЛЕННАЯ ФУНКЦИЯ: Сбалансированный отбор
    
    private static func selectBalancedSamples(
        candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)],
        desiredCount: Int,
        height: Int,
        topBottomRatio: Float
    ) -> [Sample] {
        
        // Разделяем на верхнюю и нижнюю половины
        let topHalf = candidates.filter { $0.y < height / 2 }
        let bottomHalf = candidates.filter { $0.y >= height / 2 }
        
        Logger.shared.debug("TopHalf=\(topHalf.count), BottomHalf=\(bottomHalf.count), desiredCount=\(desiredCount), topBottomRatio=\(topBottomRatio)")
        
        let topCount = topHalf.count
        let bottomCount = bottomHalf.count
        let totalCandidates = topCount + bottomCount
        
        guard totalCandidates > 0 else { return [] }
        
        #if DEBUG
        Logger.shared.debug("Кандидаты - Верх: \(topCount), Низ: \(bottomCount)")
        #endif
        
        // Используем параметр topBottomRatio для распределения выборки
        let targetTopCount = Int(Float(desiredCount) * topBottomRatio)
        let targetBottomCount = desiredCount - targetTopCount
        
        // Оптимизированная частичная сортировка по важности
        func partialSort(_ array: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)], count: Int) -> [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] {
            if array.count <= count {
                return array.sorted { $0.importance > $1.importance }
            }
            var arrayCopy = array
            arrayCopy.selectTop(count: count) { $0.importance > $1.importance }
            return Array(arrayCopy.prefix(count))
        }
        
        let sortedTop = partialSort(topHalf, count: targetTopCount)
        let sortedBottom = partialSort(bottomHalf, count: targetBottomCount)
        
        Logger.shared.debug("Selected top \(sortedTop.count), bottom \(sortedBottom.count)")
        
        var result: [Sample] = []
        result.reserveCapacity(desiredCount)
        
        // Берём лучшие из каждой половины
        for c in sortedTop {
            result.append(Sample(x: c.x, y: c.y, color: c.color))
        }
        
        for c in sortedBottom {
            result.append(Sample(x: c.x, y: c.y, color: c.color))
        }
        
        #if DEBUG
        Logger.shared.debug("Взято: \(sortedTop.count) сверху, \(sortedBottom.count) снизу")
        #endif
        
        // Если одна половина дала меньше - добираем из другой
        if result.count < desiredCount {
            let needed = desiredCount - result.count
            
            // ИСПРАВЛЕНИЕ: Используем Set для O(1) поиска вместо O(n²)
            struct PixelCoord: Hashable {
                let x: Int
                let y: Int
            }
            
            let selectedCoords = Set(sortedTop.map { PixelCoord(x: $0.x, y: $0.y) })
                .union(sortedBottom.map { PixelCoord(x: $0.x, y: $0.y) })
            
            // ИСПРАВЛЕНИЕ: Правильное использование closure parameter
            let remainingTop = topHalf.filter { candidate in
                !selectedCoords.contains(PixelCoord(x: candidate.x, y: candidate.y))
            }
            let remainingBottom = bottomHalf.filter { candidate in
                !selectedCoords.contains(PixelCoord(x: candidate.x, y: candidate.y))
            }
            
            let allRemaining = remainingTop + remainingBottom
            
            // Сортируем оставшиеся по важности
            let sortedRemaining = allRemaining.sorted { $0.importance > $1.importance }
            
            for i in 0..<min(needed, sortedRemaining.count) {
                let c = sortedRemaining[i]
                result.append(Sample(x: c.x, y: c.y, color: c.color))
            }
            
            Logger.shared.debug("Added extra pixels from remaining candidates: count=\(min(needed, sortedRemaining.count))")
            
            #if DEBUG
            Logger.shared.debug("Добавлено ещё \(min(needed, sortedRemaining.count)) из оставшихся")
            #endif
        }
        
        // Обрезаем избыток
        if result.count > desiredCount {
            result = Array(result.prefix(desiredCount))
        }
        
        #if DEBUG
        let finalTop = result.filter { $0.y < height / 2 }
        let finalBottom = result.filter { $0.y >= height / 2 }
        Logger.shared.debug("Финальное распределение - Верх: \(finalTop.count), Низ: \(finalBottom.count)")
        #endif
        
        Logger.shared.info("Final samples count: \(result.count)")
        return result
    }
    
    // MARK: - Private helper methods
    
    private static func gatherImportantPixels(
        cache: PixelCache,
        width: Int,
        height: Int,
        strideX: Int,
        strideY: Int,
        params: SamplingParams,
        dominantColors: [SIMD3<Float>]
    ) -> [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] {
        
        // ИСПРАВЛЕНИЕ: Более безопасная резервация памяти с лимитом
        let estimatedCapacity = min(
            (width / strideX) * (height / strideY),
            100_000 // Максимальный разумный лимит
        )
        
        var candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] = []
        candidates.reserveCapacity(estimatedCapacity)
        
        Logger.shared.debug("GatherImportantPixels: strideX=\(strideX), strideY=\(strideY), estimatedCapacity=\(estimatedCapacity)")

        _ = max(1, Int(Float(width) * ArtifactPreventionHelper.Constants.cornerMarginRatio))
        _ = max(1, Int(Float(height) * ArtifactPreventionHelper.Constants.cornerMarginRatio))
        
        for y in stride(from: 0, to: height, by: strideY) {
            for x in stride(from: 0, to: width, by: strideX) {
                guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else { continue }
                guard pixel.a > PixelCacheHelper.Constants.alphaThreshold else { continue }
                
                // Определяем тип пикселя для усиления
                let neighbors = PixelCacheHelper.getNeighborPixels(atX: x, y: y, from: cache)
                var importance = ArtifactPreventionHelper.calculateEnhancedPixelImportance(
                    r: pixel.r, g: pixel.g, b: pixel.b, a: pixel.a,
                    neighbors: neighbors,
                    params: params,
                    dominantColors: dominantColors
                )
//                
                // Минимальное усиление краёв
//                if isCornerPixel {
//                    importance *= 1.1
//                } else if isEdgePixel {
//                    importance *= 1.05
//                }
                
                let brightness = (pixel.r + pixel.g + pixel.b) / 3.0
                if brightness > 0.8 {
            importance *= 1.1
                }
                
                // Пропускаем только совсем незначительные
                if importance > ArtifactPreventionHelper.Constants.noiseThreshold * 0.5 {
                    candidates.append((
                        x: x,
                        y: y,
                        color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
                        importance: importance
                    ))
                    Logger.shared.trace("Added candidate pixel: x=\(x), y=\(y), importance=\(importance)")
                }
            }
        }
        
        // Анти-кластеризация контролируется флагом в params
        if params.applyAntiClustering {
            candidates = ArtifactPreventionHelper.applyAntiClusteringForCandidates(candidates: candidates)
            Logger.shared.debug("After anti-clustering: candidates.count=\(candidates.count)")
        }
        
        return candidates
    }
    
    private static func gatherFallbackPixels(
        cache: PixelCache,
        width: Int,
        height: Int,
        neededCount: Int
    ) -> [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] {
        
        guard neededCount > 0 else { return [] }
        
        var fallback: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] = []
        fallback.reserveCapacity(min(neededCount, width * height))
        
        let gridSize = Int(ceil(sqrt(Double(neededCount)) * 1.5))
        let strideX = max(1, Int(ceil(Float(width) / Float(gridSize))))
        let strideY = max(1, Int(ceil(Float(height) / Float(gridSize))))
        
        outer: for gridY in 0..<gridSize {
            for gridX in 0..<gridSize {
                if fallback.count >= neededCount { break outer }
                
                let x = min(gridX * strideX, width - 1)
                let y = min(gridY * strideY, height - 1)
                
                guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else { continue }
                if pixel.a > PixelCacheHelper.Constants.lowAlphaThreshold {
                    fallback.append((
                        x: x,
                        y: y,
                        color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
                        importance: 0.1
                    ))
              //      Logger.shared.trace("Added fallback pixel: x=\(x), y=\(y)")
                }
            }
        }
        return fallback
    }
}

// MARK: - Extensions

private extension SamplingParams {
    var isValid: Bool {
        // ИСПРАВЛЕНИЕ: Более полная валидация
        guard topBottomRatio >= 0.0 && topBottomRatio <= 1.0 else { return false }
        // Добавьте другие проверки параметров по необходимости:
        // guard edgeWeight >= 0 else { return false }
        // guard colorWeight >= 0 else { return false }
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
        // Use quickselect algorithm for O(n) average case performance
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
