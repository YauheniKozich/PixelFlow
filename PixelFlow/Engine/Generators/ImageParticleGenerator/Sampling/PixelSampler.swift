//
//  PixelSampler.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import CoreGraphics
import Foundation
import simd

final class DefaultPixelSampler: PixelSampler {
    
    // MARK: - Свойства
    
    private let config: ParticleGeneratorConfiguration
    
    // MARK: - Инициализация
    
    init(config: ParticleGeneratorConfiguration) {
        self.config = config
    }
    
    // MARK: - Публичный интерфейс
    
    func samplePixels(from analysis: ImageAnalysis,
                      targetCount: Int,
                      config: ParticleGeneratorConfiguration,
                      image: CGImage) throws -> [Sample] {
        
        // Создаем кэш пикселей из изображения
        let cache = try PixelCacheHelper.createPixelCache(from: image)
        
        // Конвертируем доминирующие цвета в формат с альфа-каналом
        let dominantColors4 = convertDominantColors(analysis.dominantColors)
        
        // Выбираем стратегию семплирования
        let samples = try selectSamplingStrategy(
            analysis: analysis,
            targetCount: targetCount,
            config: config,
            cache: cache,
            dominantColors4: dominantColors4
        )
        
        // Применяем коррекцию для предотвращения артефактов
        let validatedSamples = ArtifactPreventionHelper.validateAndCorrectSamples(
            samples: samples,
            cache: cache,
            targetCount: targetCount,
            imageSize: CGSize(width: cache.width, height: cache.height)
        )
        
        return validatedSamples
    }
    
    // MARK: - Приватные методы
    
    /// Выбирает стратегию семплирования в зависимости от конфигурации
    private func selectSamplingStrategy(
        analysis: ImageAnalysis,
        targetCount: Int,
        config: ParticleGeneratorConfiguration,
        cache: PixelCache,
        dominantColors4: [SIMD4<Float>]
    ) throws -> [Sample] {
        
        switch config.samplingStrategy {
        case .uniform:
            return try UniformSamplingStrategy.sample(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                cache: cache
            )
            
        case .importance:
            let params = SamplingParameters.samplingParams(from: config)
            return try ImportanceSamplingStrategy.sample(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                params: params,
                cache: cache,
                dominantColors: analysis.dominantColors
            )
            
        case .adaptive:
            let params = SamplingParameters.samplingParams(from: config)
            return try AdaptiveSamplingStrategy.sample(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                params: params,
                cache: cache,
                dominantColors: analysis.dominantColors
            )
            
        case .hybrid:
            let params = SamplingParameters.samplingParams(from: config)
            return try HybridSamplingStrategy.sample(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                params: params,
                cache: cache,
                dominantColors: analysis.dominantColors
            )
            
        case .advanced(let algorithm):
            let params = SamplingParameters.samplingParams(from: config)
            return try AdvancedPixelSampler.samplePixels(
                algorithm: algorithm,
                cache: cache,
                targetCount: targetCount,
                params: params,
                dominantColors: dominantColors4
            )
        }
    }
    
    /// Конвертирует доминирующие цвета из SIMD3<Float> в SIMD4<Float>
    private func convertDominantColors(_ colors3: [SIMD3<Float>]) -> [SIMD4<Float>] {
        return colors3.map { color3 in
            SIMD4<Float>(color3.x, color3.y, color3.z, 1.0)
        }
    }
}
