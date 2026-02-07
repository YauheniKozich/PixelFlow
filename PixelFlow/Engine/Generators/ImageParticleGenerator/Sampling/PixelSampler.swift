//
//  PixelSampler.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

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
                      image: CGImage,
                      screenSize: CGSize) throws -> [Sample] {
        
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

        let totalPixels = cache.width * cache.height
        if targetCount >= totalPixels {
            // Вариант 1: берем все пиксели изображения без фильтрации и дедупликации.
            // TODO: Реализовать coverage-first (сеткой гарантировать покрытие, затем добирать importance) при targetCount < totalPixels.
            var allSamples: [Sample] = []
            allSamples.reserveCapacity(totalPixels)
            for y in 0..<cache.height {
                for x in 0..<cache.width {
                    allSamples.append(Sample(x: x, y: y, color: cache.color(atX: x, y: y)))
                }
            }
            return allSamples
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
        return filterSamplesForDisplay(
            samples: validatedSamples,
            cache: cache,
            targetCount: targetCount,
            config: config,
            screenSize: screenSize
        )
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
            let params = SamplingParameters.samplingParams(from: config, analysis: analysis)
            return try ImportanceSamplingStrategy.sample(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                params: params,
                cache: cache,
                dominantColors: analysis.dominantColors // SIMD3<Float>
            )

        case .adaptive:
            let params = SamplingParameters.samplingParams(from: config, analysis: analysis)
            return try AdaptiveSamplingStrategy.sample(
                width: cache.width,
                height: cache.height,
                targetCount: targetCount,
                params: params,
                cache: cache,
                dominantColors: analysis.dominantColors // SIMD3<Float>
            )
            
        case .hybrid:
            let params = SamplingParameters.samplingParams(from: config, analysis: analysis)
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
            let params = SamplingParameters.samplingParams(from: config, analysis: analysis)
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

    // MARK: - Visible Area Filtering

    private struct DisplayTransform {
        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
    }

    private func calculateTransform(
        imageSize: CGSize,
        screenSize: CGSize,
        mode: ImageDisplayMode
    ) -> DisplayTransform {
        let aspectImage = imageSize.width / imageSize.height
        let aspectScreen = screenSize.width / screenSize.height

        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat

        switch mode {
        case .fit:
            let modeScale = min(screenSize.width / imageSize.width,
                                screenSize.height / imageSize.height)
            scaleX = modeScale
            scaleY = modeScale
            offsetX = (screenSize.width - imageSize.width * modeScale) / 2
            offsetY = (screenSize.height - imageSize.height * modeScale) / 2

        case .fill:
            let modeScale = (aspectImage > aspectScreen)
                ? screenSize.height / imageSize.height
                : screenSize.width / imageSize.width
            scaleX = modeScale
            scaleY = modeScale
            offsetX = (screenSize.width - imageSize.width * modeScale) / 2
            offsetY = (screenSize.height - imageSize.height * modeScale) / 2

        case .stretch:
            scaleX = screenSize.width / imageSize.width
            scaleY = screenSize.height / imageSize.height
            offsetX = 0
            offsetY = 0

        case .center:
            scaleX = 1.0
            scaleY = 1.0
            offsetX = (screenSize.width - imageSize.width) / 2
            offsetY = (screenSize.height - imageSize.height) / 2
        }

        return DisplayTransform(scaleX: scaleX, scaleY: scaleY, offsetX: offsetX, offsetY: offsetY)
    }

    private func visibleImageRect(
        imageSize: CGSize,
        screenSize: CGSize,
        mode: ImageDisplayMode
    ) -> CGRect {
        guard imageSize.width > 0,
              imageSize.height > 0,
              screenSize.width > 0,
              screenSize.height > 0 else {
            return CGRect(origin: .zero, size: imageSize)
        }

        let transform = calculateTransform(imageSize: imageSize, screenSize: screenSize, mode: mode)
        let scaledSize = CGSize(width: imageSize.width * transform.scaleX,
                                height: imageSize.height * transform.scaleY)
        let imageOnScreen = CGRect(x: transform.offsetX,
                                   y: transform.offsetY,
                                   width: scaledSize.width,
                                   height: scaledSize.height)
        let screenRect = CGRect(origin: .zero, size: screenSize)
        let visibleScreen = imageOnScreen.intersection(screenRect)
        if visibleScreen.isNull || visibleScreen.width <= 0 || visibleScreen.height <= 0 {
            return CGRect(origin: .zero, size: imageSize)
        }

        let visibleImage = CGRect(
            x: (visibleScreen.minX - transform.offsetX) / transform.scaleX,
            y: (visibleScreen.minY - transform.offsetY) / transform.scaleY,
            width: visibleScreen.width / transform.scaleX,
            height: visibleScreen.height / transform.scaleY
        )

        return visibleImage.intersection(CGRect(origin: .zero, size: imageSize))
    }

    private func filterSamplesForDisplay(
        samples: [Sample],
        cache: PixelCache,
        targetCount: Int,
        config: ParticleGenerationConfig,
        screenSize: CGSize
    ) -> [Sample] {
        guard screenSize.width > 0, screenSize.height > 0 else {
            return samples
        }

        let imageSize = CGSize(width: cache.width, height: cache.height)
        let visibleRect = visibleImageRect(
            imageSize: imageSize,
            screenSize: screenSize,
            mode: config.imageDisplayMode
        )

        // Быстрый путь: весь кадр видим
        if visibleRect.minX <= 0,
           visibleRect.minY <= 0,
           visibleRect.maxX >= imageSize.width - 1,
           visibleRect.maxY >= imageSize.height - 1 {
            return samples
        }

        let minX = max(0, Int(floor(visibleRect.minX)))
        let minY = max(0, Int(floor(visibleRect.minY)))
        let maxX = min(cache.width - 1, Int(ceil(visibleRect.maxX)) - 1)
        let maxY = min(cache.height - 1, Int(ceil(visibleRect.maxY)) - 1)

        guard minX <= maxX, minY <= maxY else {
            return samples
        }

        var filtered = samples.filter { sample in
            sample.x >= minX && sample.x <= maxX && sample.y >= minY && sample.y <= maxY
        }

        if filtered.count < targetCount {
            var used = PixelCacheHelper.usedPositions(from: filtered)
            addUniformSamplesInRect(
                to: &filtered,
                used: &used,
                cache: cache,
                minX: minX,
                minY: minY,
                maxX: maxX,
                maxY: maxY,
                targetCount: targetCount
            )
        }

        return filtered
    }

    private func addUniformSamplesInRect(
        to samples: inout [Sample],
        used: inout Set<UInt64>,
        cache: PixelCache,
        minX: Int,
        minY: Int,
        maxX: Int,
        maxY: Int,
        targetCount: Int
    ) {
        let needed = targetCount - samples.count
        guard needed > 0 else { return }

        let rectWidth = maxX - minX + 1
        let rectHeight = maxY - minY + 1
        guard rectWidth > 0, rectHeight > 0 else { return }

        let aspectRatio = Double(rectWidth) / Double(rectHeight)
        let gridHeight = max(1, Int(sqrt(Double(needed) / aspectRatio)))
        let gridWidth = max(1, Int(ceil(Double(needed) / Double(gridHeight))))

        @inline(__always)
        func gridCoord(_ index: Int, _ gridSize: Int, _ maxCoord: Int) -> Int {
            guard gridSize > 1 else { return maxCoord / 2 }
            let t = Double(index) / Double(gridSize - 1)
            return Int((t * Double(maxCoord)).rounded())
        }

        outerLoop: for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                if samples.count >= targetCount { break outerLoop }
                let x = minX + gridCoord(gx, gridWidth, rectWidth - 1)
                let y = minY + gridCoord(gy, gridHeight, rectHeight - 1)
                let key = PixelCacheHelper.positionKey(x, y)
                if used.contains(key) { continue }
                let color = cache.color(atX: x, y: y)
                samples.append(Sample(x: x, y: y, color: color))
                used.insert(key)
            }
        }

        if samples.count >= targetCount { return }

        // Рандом-дозаполнение, если не хватило
        var attempts = 0
        let maxAttempts = needed * 10
        while samples.count < targetCount && attempts < maxAttempts {
            let x = Int.random(in: minX...maxX)
            let y = Int.random(in: minY...maxY)
            let key = PixelCacheHelper.positionKey(x, y)
            if !used.contains(key) {
                let color = cache.color(atX: x, y: y)
                samples.append(Sample(x: x, y: y, color: color))
                used.insert(key)
            }
            attempts += 1
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
