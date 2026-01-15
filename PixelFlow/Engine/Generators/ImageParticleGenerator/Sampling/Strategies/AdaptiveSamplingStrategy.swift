//
//  AdaptiveSamplingStrategy.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics

enum AdaptiveSamplingStrategy {
    
    static func sample(
        width: Int,
        height: Int,
        targetCount: Int,
        params: SamplingParams,
        cache: PixelCache,
        dominantColors: [SIMD3<Float>] = []
    ) throws -> [Sample] {
        
        guard targetCount > 0 else { return [] }
        
        let totalPixels = width * height
        if targetCount >= totalPixels {
            return try UniformSamplingStrategy.sample(
                width: width,
                height: height,
                targetCount: totalPixels,
                cache: cache
            )
        }
        
        // Кэшируем все цвета изображения
        var colorCache = [SIMD4<Float>](repeating: SIMD4<Float>(0,0,0,0), count: totalPixels)
        for y in 0..<height {
            for x in 0..<width {
                colorCache[y * width + x] = cache.color(atX: x, y: y)
            }
        }
        
        // Используем пропорции из params
        let importantRatio = params.importantSamplingRatio
        let topBottomRatio = params.topBottomRatio
        
        let importantCount = Int(Float(targetCount) * importantRatio)
        let uniformCount = targetCount - importantCount
        
        var result = try ImportanceSamplingStrategy.sample(
            width: width,
            height: height,
            targetCount: importantCount,
            params: params,
            cache: cache,
            dominantColors: dominantColors
        )
        
        #if DEBUG
        var topCount = 0
        var bottomCount = 0
        for sample in result {
            if sample.y < height / 2 {
                topCount += 1
            } else {
                bottomCount += 1
            }
        }
        Logger.shared.debug("После ImportanceSampling (\(result.count)): Top \(topCount), Bottom \(bottomCount)")
        #endif
        
        var used = [Bool](repeating: false, count: totalPixels)
        for sample in result {
            used[sample.y * width + sample.x] = true
        }
        
        if result.count < targetCount && uniformCount > 0 {
            try addBalancedUniformSamples(
                to: &result,
                used: &used,
                width: width,
                height: height,
                targetCount: targetCount,
                cache: cache,
                colorCache: colorCache,
                topBottomRatio: topBottomRatio
            )
        }
        
        #if DEBUG
        topCount = 0
        bottomCount = 0
        for sample in result {
            if sample.y < height / 2 {
                topCount += 1
            } else {
                bottomCount += 1
            }
        }
        Logger.shared.debug("После добавления uniform (\(result.count)): Top \(topCount), Bottom \(bottomCount)")
        #endif
        
        return result
    }
    
    // НОВАЯ ФУНКЦИЯ: Сбалансированное добавление uniform сэмплов
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
        
        var currentTop = 0
        for sample in samples {
            if sample.y < height / 2 {
                currentTop += 1
            }
        }
        let currentBottom = samples.count - currentTop
        
        let targetTop = Int(Float(targetCount) * topBottomRatio)
        let targetBottom = targetCount - targetTop
        
        let needTop = max(0, targetTop - currentTop)
        let needBottom = max(0, targetBottom - currentBottom)
        
        // Создаём сетку с шагом, чтобы минимизировать итерации
        let gridSize = Int(ceil(sqrt(Double(needed)) * 1.5))
        let stepX = max(1, width / gridSize)
        let stepY = max(1, (height / 2) / gridSize)
        
        var addedTop = 0
        var addedBottom = 0
        
        // Добавляем из верхней половины с шагом stride
        if needTop > 0 {
            outerTop: for y in stride(from: 0, to: height / 2, by: stepY) {
                for x in stride(from: 0, to: width, by: stepX) {
                    if addedTop >= needTop { break outerTop }
                    let keyIndex = y * width + x
                    if !used[keyIndex] {
                        used[keyIndex] = true
                        samples.append(Sample(x: x, y: y, color: colorCache[keyIndex]))
                        addedTop += 1
                    }
                }
            }
        }
        
        // Добавляем из нижней половины с шагом stride
        if needBottom > 0 {
            outerBottom: for y in stride(from: height / 2, to: height, by: stepY) {
                for x in stride(from: 0, to: width, by: stepX) {
                    if addedBottom >= needBottom { break outerBottom }
                    let keyIndex = y * width + x
                    if !used[keyIndex] {
                        used[keyIndex] = true
                        samples.append(Sample(x: x, y: y, color: colorCache[keyIndex]))
                        addedBottom += 1
                    }
                }
            }
        }
        
        Logger.shared.debug("Добавлено uniform сэмплов: Top \(addedTop), Bottom \(addedBottom)")
        
        if samples.count < targetCount {
            let stillNeeded = targetCount - samples.count
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
    }
    
    // НОВАЯ ФУНКЦИЯ: Сбалансированные случайные сэмплы с streaming выборкой
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
        
        // Валидация topBottomRatio
        let ratio = min(max(topBottomRatio, 0.0), 1.0)
        
        var currentTop = 0
        for sample in samples {
            if sample.y < height / 2 {
                currentTop += 1
            }
        }
        _ = samples.count - currentTop
        
        var addedTop = 0
        var addedBottom = 0
        
        let targetTop = Int(Float(samples.count + needed) * ratio)
        _ = samples.count + needed - targetTop
        
        // Собираем свободные позиции для верхней и нижней половин (без shuffle)
        var freeTopPositions: [(Int, Int)] = []
        var freeBottomPositions: [(Int, Int)] = []
        
        for y in 0..<height {
            let isTop = y < height / 2
            for x in 0..<width {
                if !used[y * width + x] {
                    if isTop {
                        freeTopPositions.append((x, y))
                    } else {
                        freeBottomPositions.append((x, y))
                    }
                }
            }
        }
        
        // Streaming выборка случайных индексов без полного перемешивания
        var topIndex = 0
        var bottomIndex = 0
        
        func randomIndex(max: Int) -> Int {
            return Int.random(in: 0..<max)
        }
        
        func addSample(from positions: inout [(Int, Int)], index: inout Int, addedCount: inout Int) {
            let swapIndex = index + randomIndex(max: positions.count - index)
            positions.swapAt(index, swapIndex)
            let (x, y) = positions[index]
            index += 1
            let keyIndex = y * width + x
            used[keyIndex] = true
            samples.append(Sample(x: x, y: y, color: colorCache[keyIndex]))
            addedCount += 1
        }
        
        while (addedTop + addedBottom) < needed {
            let totalSamples = samples.count + 1
            let topRatioCurrent = Float(currentTop + addedTop) / Float(totalSamples)
            let shouldAddTop = topRatioCurrent < ratio
            
            if shouldAddTop && topIndex < freeTopPositions.count {
                addSample(from: &freeTopPositions, index: &topIndex, addedCount: &addedTop)
            } else if !shouldAddTop && bottomIndex < freeBottomPositions.count {
                addSample(from: &freeBottomPositions, index: &bottomIndex, addedCount: &addedBottom)
            } else {
                // Если не хватает позиций в нужной половине, пытаемся из другой
                if topIndex < freeTopPositions.count {
                    addSample(from: &freeTopPositions, index: &topIndex, addedCount: &addedTop)
                } else if bottomIndex < freeBottomPositions.count {
                    addSample(from: &freeBottomPositions, index: &bottomIndex, addedCount: &addedBottom)
                } else {
                    // Нет свободных позиций
                    break
                }
            }
        }
        
        Logger.shared.debug("Random добавлено сэмплов: Top \(addedTop), Bottom \(addedBottom)")
        
        if (addedTop + addedBottom) < needed {
            Logger.shared.warning("Не удалось добавить все случайные сэмплы (\(addedTop + addedBottom)/\(needed))")
        }
    }
}
