//
//  ImageAnalyzer.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import CoreGraphics
import Accelerate
import simd
import os

// MARK: Supporting structures

/// Один‑единственный объект, собирающий статистику из нескольких потоков.
private final class PixelStatistics {
    var totalR: Float = 0
    var totalG: Float = 0
    var totalB: Float = 0
    var totalBrightness: Float = 0
    var totalSaturation: Float = 0
    var minBrightness: Float = 1.0
    var maxBrightness: Float = 0.0
    var coloredPixels: Int = 0
    var edgePixels: Int = 0
    
    private var lock = os_unfair_lock_s()
    
    /// Потокобезопасное объединение с другим объектом.
    func combine(with other: PixelStatistics) {
        os_unfair_lock_lock(&lock)
        totalR += other.totalR
        totalG += other.totalG
        totalB += other.totalB
        totalBrightness += other.totalBrightness
        totalSaturation += other.totalSaturation
        minBrightness = Swift.min(minBrightness, other.minBrightness)
        maxBrightness = Swift.max(maxBrightness, other.maxBrightness)
        coloredPixels += other.coloredPixels
        edgePixels += other.edgePixels
        os_unfair_lock_unlock(&lock)
    }
}

// MARK: Итоговый результат анализа

private struct AnalysisResult {
    let averageColor: SIMD3<Float>
    let brightness: Float
    let saturation: Float
    let pixelDensity: Float
    let contrast: Float
    let complexity: Int
    let dominantColors: [SIMD3<Float>]
    let colorVariance: Float
    let edgeDensity: Float
}

// MARK: Основной класс‑анализатор

final class DefaultImageAnalyzer: ImageAnalyzer {
    
    // Параметры производительности (для будущего расширения)
    private let config: PerformanceParams
    
    init(config: PerformanceParams) {
        self.config = config
    }
    
    // --------------------------------------------------------
    // MARK: Public API
    // --------------------------------------------------------
    func analyze(image: CGImage) throws -> ImageAnalysis {
        guard image.width > 0 && image.height > 0 else {
            throw GeneratorError.invalidImage
        }
        
        // Даун‑сэмплинг (если изображение слишком велико)
        let downsampled = downsampleIfNeeded(image, maxDimension: 2048)
        
        // Однопроходный, многопоточный анализ
        let result = try performSinglePassAnalysis(downsampled)
        
        // Формируем финальный `ImageAnalysis`
        return ImageAnalysis(
            width: downsampled.width,
            height: downsampled.height,
            averageColor: result.averageColor,
            contrast: result.contrast,
            brightness: result.brightness,
            pixelDensity: result.pixelDensity,
            complexity: result.complexity,
            dominantColors: result.dominantColors,
            colorVariance: result.colorVariance,
            edgeDensity: result.edgeDensity,
            saturation: result.saturation
        )
    }
    
    // MARK: Private helpers
    
    /// Даун‑сэмплинг с автоматически‑выравненным stride.
    private func downsampleIfNeeded(_ image: CGImage, maxDimension: Int) -> CGImage {
        let w = image.width
        let h = image.height
        
        // Если изображение уже вписывается – возвращаем как есть
        guard w > maxDimension || h > maxDimension else { return image }
        
        let scale = CGFloat(maxDimension) / CGFloat(max(w, h))
        let newW = Int(CGFloat(w) * scale)
        let newH = Int(CGFloat(h) * scale)
        
        // 0‑bytesPerRow → система будет выбирать выравненный stride
//        guard let ctx = CGContext(
//            data: nil,
//            width: newW,
//            height: newH,
//            bitsPerComponent: 8,
//            bytesPerRow: w * 4,
//            space: CGColorSpaceCreateDeviceRGB(),
//            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
//        ) else {
//            Logger.shared.error("Failed to create down‑sampling CGContext")
//            return image
//        }
        
        guard let ctx = GraphicsUtils.createBitmapContext(width: newW, height: newH) else {
            Logger.shared.error("Не удалось создать CGContext для уменьшения разрешения")
            return image
        }
        
        ctx.interpolationQuality = .high
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: newW, height: newH))
        return ctx.makeImage() ?? image
    }
    
    /// Самый быстрый однопроходный анализ (многопоточный, но без гонок).
    private func performSinglePassAnalysis(_ image: CGImage) throws -> AnalysisResult {
        let w = image.width
        let h = image.height
        let totalPixels = w * h
        
        // -----------------------------------------------------------------
        // Доступ к сырым байтам + корректный stride
        // -----------------------------------------------------------------
        guard let dataProvider = image.dataProvider,
              let cfData = dataProvider.data,
              let rawPtr = CFDataGetBytePtr(cfData) else {
            throw GeneratorError.analysisFailed(reason: "Cannot access image data")
        }
        
        // Важно использовать реальный stride, а не `width*4`.
        let bytesPerRow = image.bytesPerRow
        let bytesPerPixel = 4
        
        // -----------------------------------------------------------------
        // Параллельный проход по строкам
        // -----------------------------------------------------------------
        let globalStats = PixelStatistics()          // один объект → единый lock
        var globalHistogram = [SIMD3<Float>: Int]()
        var histogramLock = os_unfair_lock_s()
        
        DispatchQueue.concurrentPerform(iterations: h) { row in
            let localStats = PixelStatistics()      // отдельный объект для строки
            var localHist = [SIMD3<Float>: Int]()
            var prevBrightness: Float = 0          // сбрасываем в начале строки
            
            let rowStart = row * bytesPerRow
            for x in 0..<w {
                let offset = rowStart + x * bytesPerPixel
                let r = Float(rawPtr[offset])       / 255.0
                let g = Float(rawPtr[offset + 1])   / 255.0
                let b = Float(rawPtr[offset + 2])   / 255.0
                let a = Float(rawPtr[offset + 3])   / 255.0
                
                // Пропускаем почти прозрачные пиксели
                guard a > 0.1 else { continue }
                
                // ---------- Суммируем основные метрики ----------
                let aR = r * a, aG = g * a, aB = b * a
                localStats.totalR += aR
                localStats.totalG += aG
                localStats.totalB += aB
                localStats.coloredPixels += 1
                
                // ---------- Яркость ----------
                let brightness = (r + g + b) / 3.0
                localStats.totalBrightness += brightness
                localStats.minBrightness = Swift.min(localStats.minBrightness, brightness)
                localStats.maxBrightness = Swift.max(localStats.maxBrightness, brightness)
                
                // ---------- Насыщенность ----------
                let mx = max(r, g, b)
                let mn = min(r, g, b)
                let sat = mx > 0 ? (mx - mn) / mx : 0
                localStats.totalSaturation += sat
                
                // ---------- Гистограмма (квантованная) ----------
                let quant = SIMD3<Float>(round(r * 8) / 8,
                                        round(g * 8) / 8,
                                        round(b * 8) / 8)
                localHist[quant, default: 0] += 1
                
                // ---------- Простейшее горизонтальное Sobel‑детектирование ----------
                let diff = abs(brightness - prevBrightness)
                if diff > 0.15 { localStats.edgePixels += 1 }
                prevBrightness = brightness
            }
            
            // Объединяем локальные данные в глобальные (lock внутри класса)
            globalStats.combine(with: localStats)
            
            // Гистограмма – отдельный lock, так как это обычный словарь
            os_unfair_lock_lock(&histogramLock)
            for (col, cnt) in localHist {
                globalHistogram[col, default: 0] += cnt
            }
            os_unfair_lock_unlock(&histogramLock)
        }
        
        // -----------------------------------------------------------------
        // Пост‑обработка (расчёт итоговых метрик)
        // -----------------------------------------------------------------
        guard globalStats.coloredPixels > 0 else {
            throw GeneratorError.analysisFailed(reason: "No colored pixels found")
        }
        
        // Средние значения
        let avgR = globalStats.totalR / Float(globalStats.coloredPixels)
        let avgG = globalStats.totalG / Float(globalStats.coloredPixels)
        let avgB = globalStats.totalB / Float(globalStats.coloredPixels)
        let avgBrightness   = globalStats.totalBrightness / Float(globalStats.coloredPixels)
        let avgSaturation   = globalStats.totalSaturation / Float(globalStats.coloredPixels)
        let pixelDensity    = Float(globalStats.coloredPixels) / Float(totalPixels)
        
        // Контраст (разница max/min яркости)
        let contrast: Float = (globalStats.maxBrightness > globalStats.minBrightness)
            ? (globalStats.maxBrightness - globalStats.minBrightness) / globalStats.maxBrightness
            : 0.5
        
        // Доминирующие цвета (5 самых частых)
        let dominantColors = globalHistogram.sorted { $0.value > $1.value }
                                               .prefix(5)
                                               .map { $0.key }
        
        // Дисперсия цветов
        let colorVariance = calculateColorVariance(
            histogram: globalHistogram,
            averageColor: SIMD3<Float>(avgR, avgG, avgB)
        )
        
        // Плотность краёв и «сложность» (0‑10)
        let edgeDensity = Float(globalStats.edgePixels) / Float(totalPixels)
        let complexity   = Int(min(edgeDensity * 20, 10))
        
        return AnalysisResult(
            averageColor: SIMD3<Float>(avgR, avgG, avgB),
            brightness: avgBrightness,
            saturation: avgSaturation,
            pixelDensity: pixelDensity,
            contrast: contrast,
            complexity: complexity,
            dominantColors: dominantColors,
            colorVariance: colorVariance,
            edgeDensity: edgeDensity
        )
    }
    
    // MARK: Helper – цветовая дисперсия

    private func calculateColorVariance(
        histogram: [SIMD3<Float>: Int],
        averageColor: SIMD3<Float>
    ) -> Float {
        var sumSq: Float = 0
        var total = 0
        
        for (col, cnt) in histogram {
            let diff = col - averageColor
            let d2 = simd_length_squared(diff)
            sumSq += d2 * Float(cnt)
            total += cnt
        }
        guard total > 0 else { return 0.0 }
        return sqrt(sumSq / Float(total))
    }
}
