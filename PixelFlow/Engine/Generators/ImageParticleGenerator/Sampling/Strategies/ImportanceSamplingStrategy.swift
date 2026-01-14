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
    
    static func sample(width: Int,
                      height: Int,
                      targetCount: Int,
                  params: SamplingParams,
                  cache: PixelCache,
                  dominantColors: [SIMD3<Float>] = []) throws -> [Sample] {
        
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
        
        // Определяем шаг сканирования для оптимизации
        let scanStrideX = max(1, width / 512)
        let scanStrideY = max(1, height / 512)
        
        Logger.shared.debug("Сканирование изображения \(width)x\(height) с шагом \(scanStrideX)x\(scanStrideY)")
        
        // Сбор важных пикселей
        var candidates = gatherImportantPixels(
            cache: cache,
            width: width,
            height: height,
            strideX: scanStrideX,
            strideY: scanStrideY,
            params: params,
            dominantColors: dominantColors
        )
        
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
        
        // Финальный отбор
        let finalSamples = selectFinalSamples(
            sortedCandidates: candidates,
            desiredCount: targetCount,
            cache: cache,
            width: width,
            height: height,
            strideX: scanStrideX,
            strideY: scanStrideY,
            params: params
        )
        
        Logger.shared.info("Возврат \(finalSamples.count) окончательных сэмплов")
        return finalSamples
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
        
        var candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] = []
        candidates.reserveCapacity((width / strideX) * (height / strideY))
        
        // Рассчитываем границы для усиления краев
        let edgeMarginX = max(1, Int(Float(width) * ArtifactPreventionHelper.Constants.cornerMarginRatio))
        let edgeMarginY = max(1, Int(Float(height) * ArtifactPreventionHelper.Constants.cornerMarginRatio))
        let cornerSize = max(edgeMarginX, edgeMarginY)
        
        for y in stride(from: 0, to: height, by: strideY) {
            for x in stride(from: 0, to: width, by: strideX) {
                guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else { continue }
                guard pixel.a > PixelCacheHelper.Constants.alphaThreshold else { continue }
                
                // Определяем тип пикселя для усиления
                let isEdgePixel = x < edgeMarginX || x >= width - edgeMarginX ||
                                 y < edgeMarginY || y >= height - edgeMarginY
                
                let isCornerPixel = (x < cornerSize && y < cornerSize) ||
                                   (x >= width - cornerSize && y < cornerSize) ||
                                   (x < cornerSize && y >= height - cornerSize) ||
                                   (x >= width - cornerSize && y >= height - cornerSize)
                
                let neighbors = PixelCacheHelper.getNeighborPixels(atX: x, y: y, from: cache)
                var importance = ArtifactPreventionHelper.calculateEnhancedPixelImportance(
                    r: pixel.r, g: pixel.g, b: pixel.b, a: pixel.a,
                    neighbors: neighbors,
                    params: params,
                    dominantColors: dominantColors
                )
                
                // Применяем усиления
                if isCornerPixel {
                    importance *= ArtifactPreventionHelper.Constants.edgeBias * 1.3
                } else if isEdgePixel {
                    importance *= ArtifactPreventionHelper.Constants.edgeBias
                }
                
                // Усиление ярких пикселей
                let brightness = (pixel.r + pixel.g + pixel.b) / 3.0
                if brightness > 0.8 {
                    importance *= ArtifactPreventionHelper.Constants.brightnessBoost
                }
                
                // Фильтр шума
                if importance > ArtifactPreventionHelper.Constants.noiseThreshold {
                    candidates.append((
                        x: x,
                        y: y,
                        color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
                        importance: importance
                    ))
                }
            }
        }
        
        // Анти-кластеризация
        candidates = ArtifactPreventionHelper.applyAntiClusteringForCandidates(candidates: candidates)
        
        candidates.sort { $0.importance > $1.importance }
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
        
        let strideX = max(1, width / 100)
        let strideY = max(1, height / 100)
        
        outer: for y in stride(from: 0, to: height, by: strideY) {
            for x in stride(from: 0, to: width, by: strideX) {
                guard let pixel = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) else { continue }
                if pixel.a > PixelCacheHelper.Constants.lowAlphaThreshold {
                    fallback.append((
                        x: x,
                        y: y,
                        color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
                        importance: 0.1
                    ))
                    if fallback.count >= neededCount { break outer }
                }
            }
        }
        return fallback
    }
    
    private static func selectFinalSamples(
        sortedCandidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)],
        desiredCount: Int,
        cache: PixelCache,
        width: Int,
        height: Int,
        strideX: Int,
        strideY: Int,
        params: SamplingParams
    ) -> [Sample] {
        
        guard !sortedCandidates.isEmpty else { return [] }
        
        var result: [Sample] = []
        result.reserveCapacity(desiredCount)
        
        // Основные (самые важные) - 60%
        let baseCount = Int(Float(desiredCount) * 0.6)
        let take = min(baseCount, sortedCandidates.count)
        for i in 0..<take {
            let c = sortedCandidates[i]
            result.append(Sample(x: c.x, y: c.y, color: c.color))
        }
        
        // Взвешенные случайные
        let bonusCount = desiredCount - result.count
        if bonusCount > 0 && sortedCandidates.count > take {
            let remaining = Array(sortedCandidates[take...])
            result.append(contentsOf: ArtifactPreventionHelper.selectWeightedSamples(
                from: remaining,
                count: bonusCount
            ))
        }
        
        // Если всё ещё не хватает – случайные без повторов
        if result.count < desiredCount {
            let needed = desiredCount - result.count
            _ = Set(result.map { PixelCacheHelper.PixelCoordinate(x: $0.x, y: $0.y) })
            result.append(contentsOf: ArtifactPreventionHelper.selectRandomSamples(
                from: sortedCandidates,
                count: needed
            ))
        }
        
        // Обрезаем избыточные
        if result.count > desiredCount {
            result = Array(result.prefix(desiredCount))
        }
        
        return result
    }
}
