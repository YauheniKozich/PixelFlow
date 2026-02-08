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

    // MARK: - Properties

    private let config: ParticleGenerationConfig

    // MARK: - PixelSamplerProtocol

    var samplingStrategy: SamplingStrategy {
        config.samplingStrategy
    }

    var supportsAdaptiveSampling: Bool { true }
    
    // MARK: - Initialization
    
    init(config: ParticleGenerationConfig) {
        self.config = config
    }
    
    // MARK: - Public Interface
    
    func samplePixels(
        from analysis: ImageAnalysis,
        targetCount: Int,
        config: ParticleGenerationConfig,
        image: CGImage,
        screenSize: CGSize
    ) throws -> [Sample] {
        
        let cache = try createPixelCache(from: image)
        try validateTargetCount(targetCount)
        
        // Если требуется больше сэмплов, чем пикселей - вернуть все пиксели
        if shouldReturnAllPixels(targetCount: targetCount, cache: cache) {
            return sampleAllPixels(from: cache)
        }
        
        let samples = try generateSamples(
            analysis: analysis,
            targetCount: targetCount,
            config: config,
            cache: cache
        )
        
        let validatedSamples = validateSamples(samples, cache: cache, targetCount: targetCount)
        
        #if DEBUG
        // logSampleDistribution(validatedSamples, cacheHeight: cache.height)
        #endif
        
        return filterSamplesForDisplay(
            samples: validatedSamples,
            cache: cache,
            targetCount: targetCount,
            config: config,
            screenSize: screenSize
        )
    }
    
    // MARK: - Pixel Cache Creation
    
    private func createPixelCache(from image: CGImage) throws -> PixelCache {
        do {
            return try PixelCacheHelper.createPixelCache(from: image)
        } catch {
            Logger.shared.error("Failed to create pixel cache: \(error)")
            throw SamplingError.cacheCreationFailed(underlying: error)
        }
    }
    
    // MARK: - Validation
    
    private func validateTargetCount(_ targetCount: Int) throws {
        guard targetCount > 0 else {
            throw SamplingError.invalidConfiguration
        }
    }
    
    private func shouldReturnAllPixels(targetCount: Int, cache: PixelCache) -> Bool {
        let totalPixels = cache.width * cache.height
        return targetCount >= totalPixels
    }
    
    // MARK: - Sampling
    
    private func sampleAllPixels(from cache: PixelCache) -> [Sample] {
        let totalPixels = cache.width * cache.height
        var allSamples: [Sample] = []
        allSamples.reserveCapacity(totalPixels)
        
        for y in 0..<cache.height {
            for x in 0..<cache.width {
                let color = cache.color(atX: x, y: y)
                allSamples.append(Sample(x: x, y: y, color: color))
            }
        }
        
        return allSamples
    }
    
    private func generateSamples(
        analysis: ImageAnalysis,
        targetCount: Int,
        config: ParticleGenerationConfig,
        cache: PixelCache
    ) throws -> [Sample] {
        
        let samples = try selectSamplingStrategy(
            analysis: analysis,
            targetCount: targetCount,
            config: config,
            cache: cache
        )
        
        guard !samples.isEmpty else {
            throw SamplingError.insufficientSamples
        }
        
        return samples
    }
    
    private func validateSamples(
        _ samples: [Sample],
        cache: PixelCache,
        targetCount: Int
    ) -> [Sample] {
        // ВАЖНО: Importance стратегия уже включает внутреннюю балансировку через
        // selectBalancedSamples и применяет topBottomRatio, поэтому дополнительная
        // валидация может нарушить тщательно рассчитанное распределение.
        // Остальные стратегии требуют дополнительной проверки и коррекции.
        
        // if config.samplingStrategy == .importance {
        //     return samples
        // }
        
        return ArtifactPreventionHelper.validateAndCorrectSamples(
            samples: samples,
            cache: cache,
            targetCount: targetCount,
            imageSize: CGSize(width: cache.width, height: cache.height)
        )
    }
    
    // MARK: - Sampling Strategy Selection
    
    /// Выбирает стратегию семплирования в зависимости от конфигурации
    private func selectSamplingStrategy(
        analysis: ImageAnalysis,
        targetCount: Int,
        config: ParticleGenerationConfig,
        cache: PixelCache
    ) throws -> [Sample] {
        
        switch config.samplingStrategy {
        case .uniform:
            return try sampleUniform(cache: cache, targetCount: targetCount)
            
        case .importance:
            return try sampleImportance(
                cache: cache,
                targetCount: targetCount,
                config: config,
                analysis: analysis
            )
            
        case .adaptive:
            return try sampleAdaptive(
                cache: cache,
                targetCount: targetCount,
                config: config,
                analysis: analysis
            )
            
        case .hybrid:
            return try sampleHybrid(
                cache: cache,
                targetCount: targetCount,
                config: config,
                analysis: analysis
            )
            
        case .advanced(let algorithm):
            return try sampleAdvanced(
                algorithm: algorithm,
                cache: cache,
                targetCount: targetCount,
                config: config,
                analysis: analysis
            )
        }
    }
    
    // MARK: - Individual Sampling Strategies
    
    private func sampleUniform(cache: PixelCache, targetCount: Int) throws -> [Sample] {
        return try UniformSamplingStrategy.sample(
            width: cache.width,
            height: cache.height,
            targetCount: targetCount,
            cache: cache
        )
    }
    
    private func sampleImportance(
        cache: PixelCache,
        targetCount: Int,
        config: ParticleGenerationConfig,
        analysis: ImageAnalysis
    ) throws -> [Sample] {
        let params = SamplingParameters.samplingParams(from: config, analysis: analysis)
        return try ImportanceSamplingStrategy.sample(
            width: cache.width,
            height: cache.height,
            targetCount: targetCount,
            params: params,
            cache: cache,
            dominantColors: analysis.dominantColors
        )
    }
    
    private func sampleAdaptive(
        cache: PixelCache,
        targetCount: Int,
        config: ParticleGenerationConfig,
        analysis: ImageAnalysis
    ) throws -> [Sample] {
        let params = SamplingParameters.samplingParams(from: config, analysis: analysis)
        return try AdaptiveSamplingStrategy.sample(
            width: cache.width,
            height: cache.height,
            targetCount: targetCount,
            params: params,
            cache: cache,
            dominantColors: analysis.dominantColors
        )
    }
    
    private func sampleHybrid(
        cache: PixelCache,
        targetCount: Int,
        config: ParticleGenerationConfig,
        analysis: ImageAnalysis
    ) throws -> [Sample] {
        let params = SamplingParameters.samplingParams(from: config, analysis: analysis)
        return try HybridSamplingStrategy.sample(
            width: cache.width,
            height: cache.height,
            targetCount: targetCount,
            params: params,
            cache: cache,
            dominantColors: analysis.dominantColors
        )
    }
    
    private func sampleAdvanced(
        algorithm: SamplingAlgorithm,
        cache: PixelCache,
        targetCount: Int,
        config: ParticleGenerationConfig,
        analysis: ImageAnalysis
    ) throws -> [Sample] {
        // ВАЖНО: AdvancedPixelSampler требует SIMD4<Float> для dominantColors
        // Конвертируем только здесь, когда действительно необходимо
        let params = SamplingParameters.samplingParams(from: config, analysis: analysis)
        let dominantColors4 = convertDominantColors(analysis.dominantColors)
        
        return try AdvancedPixelSampler.samplePixels(
            algorithm: algorithm,
            cache: cache,
            targetCount: targetCount,
            params: params,
            dominantColors: dominantColors4
        )
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

        switch mode {
        case .fit:
            return calculateFitTransform(
                imageSize: imageSize,
                screenSize: screenSize
            )
            
        case .fill:
            return calculateFillTransform(
                imageSize: imageSize,
                screenSize: screenSize,
                aspectImage: aspectImage,
                aspectScreen: aspectScreen
            )
            
        case .stretch:
            return calculateStretchTransform(
                imageSize: imageSize,
                screenSize: screenSize
            )
            
        case .center:
            return calculateCenterTransform(
                imageSize: imageSize,
                screenSize: screenSize
            )
        }
    }
    
    private func calculateFitTransform(
        imageSize: CGSize,
        screenSize: CGSize
    ) -> DisplayTransform {
        let scale = min(
            screenSize.width / imageSize.width,
            screenSize.height / imageSize.height
        )
        let offsetX = (screenSize.width - imageSize.width * scale) / 2
        let offsetY = (screenSize.height - imageSize.height * scale) / 2
        
        return DisplayTransform(
            scaleX: scale,
            scaleY: scale,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }
    
    private func calculateFillTransform(
        imageSize: CGSize,
        screenSize: CGSize,
        aspectImage: CGFloat,
        aspectScreen: CGFloat
    ) -> DisplayTransform {
        let scale = (aspectImage > aspectScreen)
            ? screenSize.height / imageSize.height
            : screenSize.width / imageSize.width
        
        let offsetX = (screenSize.width - imageSize.width * scale) / 2
        let offsetY = (screenSize.height - imageSize.height * scale) / 2
        
        return DisplayTransform(
            scaleX: scale,
            scaleY: scale,
            offsetX: offsetX,
            offsetY: offsetY
        )
    }
    
    private func calculateStretchTransform(
        imageSize: CGSize,
        screenSize: CGSize
    ) -> DisplayTransform {
        return DisplayTransform(
            scaleX: screenSize.width / imageSize.width,
            scaleY: screenSize.height / imageSize.height,
            offsetX: 0,
            offsetY: 0
        )
    }
    
    private func calculateCenterTransform(
        imageSize: CGSize,
        screenSize: CGSize
    ) -> DisplayTransform {
        return DisplayTransform(
            scaleX: 1.0,
            scaleY: 1.0,
            offsetX: (screenSize.width - imageSize.width) / 2,
            offsetY: (screenSize.height - imageSize.height) / 2
        )
    }

    private func visibleImageRect(
        imageSize: CGSize,
        screenSize: CGSize,
        mode: ImageDisplayMode
    ) -> CGRect {
        guard isValidSize(imageSize) && isValidSize(screenSize) else {
            return CGRect(origin: .zero, size: imageSize)
        }

        let transform = calculateTransform(
            imageSize: imageSize,
            screenSize: screenSize,
            mode: mode
        )
        
        let scaledSize = CGSize(
            width: imageSize.width * transform.scaleX,
            height: imageSize.height * transform.scaleY
        )
        
        let imageOnScreen = CGRect(
            x: transform.offsetX,
            y: transform.offsetY,
            width: scaledSize.width,
            height: scaledSize.height
        )
        
        let screenRect = CGRect(origin: .zero, size: screenSize)
        let visibleScreen = imageOnScreen.intersection(screenRect)
        
        guard isValidRect(visibleScreen) else {
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
    
    private func isValidSize(_ size: CGSize) -> Bool {
        return size.width > 0 && size.height > 0
    }
    
    private func isValidRect(_ rect: CGRect) -> Bool {
        return !rect.isNull && rect.width > 0 && rect.height > 0
    }

    private func filterSamplesForDisplay(
        samples: [Sample],
        cache: PixelCache,
        targetCount: Int,
        config: ParticleGenerationConfig,
        screenSize: CGSize
    ) -> [Sample] {
        guard isValidSize(screenSize) else {
            return samples
        }

        let imageSize = CGSize(width: cache.width, height: cache.height)
        let visibleRect = visibleImageRect(
            imageSize: imageSize,
            screenSize: screenSize,
            mode: config.imageDisplayMode
        )

        // Быстрый путь: весь кадр видим
        if isEntireImageVisible(visibleRect: visibleRect, imageSize: imageSize) {
            return samples
        }

        let bounds = calculateVisibleBounds(
            visibleRect: visibleRect,
            cache: cache
        )
        
        guard isValidBounds(bounds, cache: cache) else {
            return samples
        }

        var filtered = filterSamplesInBounds(samples: samples, bounds: bounds)

        if filtered.count < targetCount {
            fillMissingSamples(
                samples: &filtered,
                cache: cache,
                bounds: bounds,
                targetCount: targetCount
            )
        }

        return filtered
    }
    
    private func isEntireImageVisible(visibleRect: CGRect, imageSize: CGSize) -> Bool {
        return visibleRect.minX <= 0 &&
               visibleRect.minY <= 0 &&
               visibleRect.maxX >= imageSize.width - 1 &&
               visibleRect.maxY >= imageSize.height - 1
    }
    
    private struct VisibleBounds {
        let minX: Int
        let minY: Int
        let maxX: Int
        let maxY: Int
    }
    
    private func calculateVisibleBounds(
        visibleRect: CGRect,
        cache: PixelCache
    ) -> VisibleBounds {
        return VisibleBounds(
            minX: max(0, Int(floor(visibleRect.minX))),
            minY: max(0, Int(floor(visibleRect.minY))),
            maxX: min(cache.width - 1, Int(ceil(visibleRect.maxX)) - 1),
            maxY: min(cache.height - 1, Int(ceil(visibleRect.maxY)) - 1)
        )
    }
    
    private func isValidBounds(_ bounds: VisibleBounds, cache: PixelCache) -> Bool {
        return bounds.minX <= bounds.maxX && bounds.minY <= bounds.maxY
    }
    
    private func filterSamplesInBounds(
        samples: [Sample],
        bounds: VisibleBounds
    ) -> [Sample] {
        return samples.filter { sample in
            sample.x >= bounds.minX &&
            sample.x <= bounds.maxX &&
            sample.y >= bounds.minY &&
            sample.y <= bounds.maxY
        }
    }
    
    private func fillMissingSamples(
        samples: inout [Sample],
        cache: PixelCache,
        bounds: VisibleBounds,
        targetCount: Int
    ) {
        var used = PixelCacheHelper.usedPositions(from: samples)
        addUniformSamplesInRect(
            to: &samples,
            used: &used,
            cache: cache,
            bounds: bounds,
            targetCount: targetCount
        )
    }

    private func addUniformSamplesInRect(
        to samples: inout [Sample],
        used: inout Set<UInt64>,
        cache: PixelCache,
        bounds: VisibleBounds,
        targetCount: Int
    ) {
        let needed = targetCount - samples.count
        guard needed > 0 else { return }

        let rectWidth = bounds.maxX - bounds.minX + 1
        let rectHeight = bounds.maxY - bounds.minY + 1
        guard rectWidth > 0, rectHeight > 0 else { return }

        addGridSamples(
            to: &samples,
            used: &used,
            cache: cache,
            bounds: bounds,
            rectWidth: rectWidth,
            rectHeight: rectHeight,
            needed: needed,
            targetCount: targetCount
        )

        if samples.count < targetCount {
            addRandomSamples(
                to: &samples,
                used: &used,
                cache: cache,
                bounds: bounds,
                needed: needed,
                targetCount: targetCount
            )
        }
    }
    
    private func addGridSamples(
        to samples: inout [Sample],
        used: inout Set<UInt64>,
        cache: PixelCache,
        bounds: VisibleBounds,
        rectWidth: Int,
        rectHeight: Int,
        needed: Int,
        targetCount: Int
    ) {
        let aspectRatio = Double(rectWidth) / Double(rectHeight)
        let gridHeight = max(1, Int(sqrt(Double(needed) / aspectRatio)))
        let gridWidth = max(1, Int(ceil(Double(needed) / Double(gridHeight))))

        outerLoop: for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                if samples.count >= targetCount { break outerLoop }
                
                let x = bounds.minX + gridCoordinate(gx, gridWidth, rectWidth - 1)
                let y = bounds.minY + gridCoordinate(gy, gridHeight, rectHeight - 1)
                let key = PixelCacheHelper.positionKey(x, y)
                
                if used.contains(key) { continue }
                
                let color = cache.color(atX: x, y: y)
                samples.append(Sample(x: x, y: y, color: color))
                used.insert(key)
            }
        }
    }
    
    @inline(__always)
    private func gridCoordinate(_ index: Int, _ gridSize: Int, _ maxCoord: Int) -> Int {
        guard gridSize > 1 else { return maxCoord / 2 }
        let t = Double(index) / Double(gridSize - 1)
        return Int((t * Double(maxCoord)).rounded())
    }
    
    private func addRandomSamples(
        to samples: inout [Sample],
        used: inout Set<UInt64>,
        cache: PixelCache,
        bounds: VisibleBounds,
        needed: Int,
        targetCount: Int
    ) {
        var attempts = 0
        let maxAttempts = needed * 10
        
        while samples.count < targetCount && attempts < maxAttempts {
            let x = Int.random(in: bounds.minX...bounds.maxX)
            let y = Int.random(in: bounds.minY...bounds.maxY)
            let key = PixelCacheHelper.positionKey(x, y)
            
            if !used.contains(key) {
                let color = cache.color(atX: x, y: y)
                samples.append(Sample(x: x, y: y, color: color))
                used.insert(key)
            }
            
            attempts += 1
        }
    }
}
