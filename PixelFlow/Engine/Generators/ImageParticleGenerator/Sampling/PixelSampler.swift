//
//  PixelSampler.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import CoreGraphics
import Foundation
import simd

import CoreGraphics
import Foundation
import simd

final class DefaultPixelSampler: PixelSampler, PixelSamplerProtocol {

    // MARK: - Свойства

    private let config: ParticleGenerationConfig

    // MARK: - PixelSamplerProtocol

    var samplingStrategy: SamplingStrategy {
        config.samplingStrategy
    }

    var supportsAdaptiveSampling: Bool { true }
    
    // MARK: - Инициализация
    
    init(config: ParticleGenerationConfig) {
        self.config = config
    }
    
    // MARK: - Публичный интерфейс
    
    func samplePixels(from analysis: ImageAnalysis,
                      targetCount: Int,
                      config: ParticleGenerationConfig,
                      image: CGImage) throws -> [Sample] {
        
        // Создаем кэш пикселей из изображения с обработкой ошибок
        let cache: PixelCache
        do {
            cache = try PixelCacheHelper.createPixelCache(from: image)
        } catch {
            Logger.shared.error("Failed to create pixel cache: \(error)")
            throw SamplingError.cacheCreationFailed(underlying: error)
        }
        
        // Валидация targetCount
        guard targetCount > 0 else {
            throw SamplingError.invalidConfiguration
        }
        
        // Выбираем стратегию семплирования
        let samples = try selectSamplingStrategy(
            analysis: analysis,
            targetCount: targetCount,
            config: config,
            cache: cache
        )
        
        // Проверяем результат
        guard !samples.isEmpty else {
            throw SamplingError.insufficientSamples
        }
        
        // ВАЖНО: Importance стратегия уже включает внутреннюю балансировку через
        // selectBalancedSamples и применяет topBottomRatio, поэтому дополнительная
        // валидация может нарушить тщательно рассчитанное распределение.
        // Остальные стратегии требуют дополнительной проверки и коррекции.
        let validatedSamples: [Sample]
//        if config.samplingStrategy == .importance {
//            validatedSamples = samples
//        } else {
            validatedSamples = ArtifactPreventionHelper.validateAndCorrectSamples(  // Внимание
                samples: samples,
                cache: cache,
                targetCount: targetCount,
                imageSize: CGSize(width: cache.width, height: cache.height)
            )
  //      }

        #if DEBUG
     //   logSampleDistribution(validatedSamples, cacheHeight: cache.height)
        #endif

        return validatedSamples
    }
    
    // MARK: - Приватные методы
    
    /// Выбирает стратегию семплирования в зависимости от конфигурации
    private func selectSamplingStrategy(
        analysis: ImageAnalysis,
        targetCount: Int,
        config: ParticleGenerationConfig,
        cache: PixelCache
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
                dominantColors: analysis.dominantColors // SIMD3<Float>
            )

        case .adaptive:
            let params = SamplingParameters.samplingParams(from: config)
            return try AdaptiveSamplingStrategy.sample(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                params: params,
                cache: cache,
                dominantColors: analysis.dominantColors // SIMD3<Float>
            )
            
        case .hybrid:
            let params = SamplingParameters.samplingParams(from: config)
            return try HybridSamplingStrategy.sample(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                params: params,
                cache: cache,
                dominantColors: analysis.dominantColors // SIMD3<Float>
            )
            
        case .advanced(let algorithm):
            // ВАЖНО: AdvancedPixelSampler требует SIMD4<Float> для dominantColors
            // Конвертируем только здесь, когда действительно необходимо
            let params = SamplingParameters.samplingParams(from: config)
            let dominantColors4 = convertDominantColors(analysis.dominantColors)

            return try AdvancedPixelSampler.samplePixels(
                algorithm: algorithm,
                cache: cache,
                targetCount: targetCount,
                params: params,
                dominantColors: dominantColors4 // SIMD4<Float>
            )
        }
    }
    
    /// Конвертирует доминирующие цвета из SIMD3<Float> в SIMD4<Float>
    /// - Parameter colors3: Массив цветов RGB без альфа-канала
    /// - Returns: Массив цветов RGBA с альфа-каналом = 1.0
    /// - Note: Используется только для AdvancedPixelSampler, который требует SIMD4
    private func convertDominantColors(_ colors3: [SIMD3<Float>]) -> [SIMD4<Float>] {
        return colors3.map { color3 in
            SIMD4<Float>(color3.x, color3.y, color3.z, 1.0)
        }
    }
    
    #if DEBUG
    /// Логирует распределение сэмплов по вертикали (один проход)
    /// - Parameters:
    ///   - samples: Массив сэмплов для анализа
    ///   - cacheHeight: Высота изображения
//    private func logSampleDistribution(_ samples: [Sample], cacheHeight: Int) {
//        guard !samples.isEmpty else {
//            Logger.shared.debug("No samples to analyze")
//            return
//        }
//        
//        var topCount = 0
//        var bottomCount = 0
//        var minY = Int.max
//        var maxY = Int.min
//        
//        // Один проход для всех метрик
//        for sample in samples {
//            if sample.y < cacheHeight / 2 {
//                topCount += 1
//            } else {
//                bottomCount += 1
//            }
//            minY = min(minY, sample.y)
//            maxY = max(maxY, sample.y)
//        }
//        
//        Logger.shared.debug("Samples from sampler - Total: \(samples.count), Top: \(topCount), Bottom: \(bottomCount)")
//        Logger.shared.debug("Sample Y range: \(minY) - \(maxY) (cache height: \(cacheHeight))")
//        
//        // Предупреждение о дисбалансе
//        let ratio = Float(topCount) / Float(samples.count)
//        if ratio < 0.3 || ratio > 0.7 {
//            Logger.shared.warning("Sample distribution may be unbalanced: \(Int(ratio * 100))% in top half")
//        }
//    }
    #endif
}


