//
//  ImageAnalysis.swift
//  PixelFlow
//
//  СТРУКТУРЫ ДАННЫХ И АНАЛИЗ ИЗОБРАЖЕНИЙ
//  для генерации частиц
//

import CoreGraphics
import CoreImage
import simd

// MARK: - Data Structures

struct ImageAnalysis: Codable {
    let width: Int
    let height: Int
    let averageColor: SIMD3<Float>
    let contrast: Float           // RMS контраст (0-1)
    let brightness: Float
    let pixelDensity: Float
    let complexity: Int           // 0-10
    let dominantColors: [SIMD3<Float>]
    let colorVariance: Float      // Дисперсия цветов
    let edgeDensity: Float        // Плотность краев (0-1)
    let saturation: Float         // Средняя насыщенность (0-1)
}

// MARK: - Image Analysis

// NOTE: Этот метод не используется в текущей реализации.
// Анализ изображений выполняется через DefaultImageAnalyzer.
// Оставлен для обратной совместимости и возможного использования в тестах.
extension ImageParticleGenerator {
    /// Анализирует изображение и вычисляет метрики для оптимизации генерации частиц
    @available(*, deprecated, message: "Use DefaultImageAnalyzer instead")
    static func analyzeImage(_ image: CGImage) -> ImageAnalysis {
        let width = image.width
        let height = image.height
        
        // Безопасная проверка размеров
        guard width > 0 && height > 0 else {
            return defaultAnalysis()
        }
        
        // Создаем контекст для чтения пикселей
        let bytesPerPixel = 4
        let bytesPerRow = width * bytesPerPixel
        let bitsPerComponent = 8
        var data = [UInt8](repeating: 0, count: Int(bytesPerRow * height))
        
        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let ctx = CGContext(
                data: &data,
                width: width,
                height: height,
                bitsPerComponent: bitsPerComponent,
                bytesPerRow: bytesPerRow,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else {
            return defaultAnalysis()
        }
        
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        
        // Переменные для анализа
        var totalR: Float = 0, totalG: Float = 0, totalB: Float = 0
        var totalSquaredR: Float = 0, totalSquaredG: Float = 0, totalSquaredB: Float = 0
        var totalSaturation: Float = 0
        var colorCount = 0
        var colorPixels = 0
        var edgePixels = 0
        
        // Для гистограммы используем более эффективную структуру
        var colorBuckets = [Int: Int]()
        
        // Первый проход: основные метрики
        for y in 0..<height {
            for x in 0..<width {
                let idx = y * bytesPerRow + x * bytesPerPixel
                let r = Float(data[idx]) / 255.0
                let g = Float(data[idx + 1]) / 255.0
                let b = Float(data[idx + 2]) / 255.0
                let a = Float(data[idx + 3]) / 255.0
                
                // Для premultiplied: восстанавливаем оригинальные цвета если нужно
                let originalR = a > 0 ? r / a : 0
                let originalG = a > 0 ? g / a : 0
                let originalB = a > 0 ? b / a : 0
                
                if a > 0.1 {
                    totalR += originalR
                    totalG += originalG
                    totalB += originalB
                    
                    totalSquaredR += originalR * originalR
                    totalSquaredG += originalG * originalG
                    totalSquaredB += originalB * originalB
                    
                    colorCount += 1
                    
                    // Насыщенность (HSV)
                    let maxVal = max(originalR, originalG, originalB)
                    let minVal = min(originalR, originalG, originalB)
                    let saturation = maxVal > 0 ? (maxVal - minVal) / maxVal : 0
                    totalSaturation += saturation
                    
                    // Квантизация цвета для гистограммы (8x8x8 = 512 корзин)
                    let quantizedR = Int(min(originalR * 7, 7))
                    let quantizedG = Int(min(originalG * 7, 7))
                    let quantizedB = Int(min(originalB * 7, 7))
                    let colorKey = (quantizedR << 6) | (quantizedG << 3) | quantizedB
                    colorBuckets[colorKey, default: 0] += 1
                    
                    if originalR > 0.1 || originalG > 0.1 || originalB > 0.1 {
                        colorPixels += 1
                    }
                }
            }
        }
        
        guard colorCount > 0 else {
            return defaultAnalysis()
        }
        
        // Вычисляем средние значения
        let avgR = totalR / Float(colorCount)
        let avgG = totalG / Float(colorCount)
        let avgB = totalB / Float(colorCount)
        let averageColor = SIMD3<Float>(avgR, avgG, avgB)
        
        // RMS контраст (стандартное отклонение яркости)
        let avgBrightness = (avgR + avgG + avgB) / 3.0
        let varianceR = totalSquaredR / Float(colorCount) - avgR * avgR
        let varianceG = totalSquaredG / Float(colorCount) - avgG * avgG
        let varianceB = totalSquaredB / Float(colorCount) - avgB * avgB
        let contrast = sqrt((varianceR + varianceG + varianceB) / 3.0)
        
        let brightness = avgBrightness
        let pixelDensity = Float(colorPixels) / Float(width * height)
        let avgSaturation = totalSaturation / Float(colorCount)
        
        // Доминирующие цвета (топ 5)
        let sortedBuckets = colorBuckets.sorted { $0.value > $1.value }
        let dominantColors = sortedBuckets.prefix(5).map { bucket -> SIMD3<Float> in
            let r = Float((bucket.key >> 6) & 0x7) / 7.0
            let g = Float((bucket.key >> 3) & 0x7) / 7.0
            let b = Float(bucket.key & 0x7) / 7.0
            return SIMD3<Float>(r, g, b)
        }
        
        // Дисперсия цветов (нормализованная)
        let colorVariance = min(contrast * 2.0, 1.0)
        
        // Упрощенный расчет краев (Sobel-like)
        for y in 1..<height-1 {
            for x in 1..<width-1 {
                let idx = y * bytesPerRow + x * bytesPerPixel
                
                // Горизонтальный градиент
                let leftIdx = idx - bytesPerPixel
                let rightIdx = idx + bytesPerPixel
                
                let leftBrightness = brightnessAtPixel(data, idx: leftIdx, bytesPerRow: bytesPerRow)
                let rightBrightness = brightnessAtPixel(data, idx: rightIdx, bytesPerRow: bytesPerRow)
                let horizontalGrad = abs(leftBrightness - rightBrightness)
                
                // Вертикальный градиент
                let topIdx = idx - bytesPerRow
                let bottomIdx = idx + bytesPerRow
                
                let topBrightness = brightnessAtPixel(data, idx: topIdx, bytesPerRow: bytesPerRow)
                let bottomBrightness = brightnessAtPixel(data, idx: bottomIdx, bytesPerRow: bytesPerRow)
                let verticalGrad = abs(topBrightness - bottomBrightness)
                
                if (horizontalGrad + verticalGrad) > 0.3 {
                    edgePixels += 1
                }
            }
        }
        
        let edgeDensity = Float(edgePixels) / Float((width - 2) * (height - 2))
        
        // Сложность на основе градиентов
        let complexity = min(edgePixels * 10 / (width * height), 10)
        
        return ImageAnalysis(
            width: width,
            height: height,
            averageColor: averageColor,
            contrast: min(contrast, 1.0),
            brightness: brightness,
            pixelDensity: pixelDensity,
            complexity: complexity,
            dominantColors: dominantColors,
            colorVariance: colorVariance,
            edgeDensity: min(edgeDensity, 1.0),
            saturation: avgSaturation
        )
    }
    
    // Вспомогательная функция для яркости пикселя
    private static func brightnessAtPixel(_ data: [UInt8], idx: Int, bytesPerRow: Int) -> Float {
        guard idx >= 0 && idx + 2 < data.count else { return 0 }
        let r = Float(data[idx]) / 255.0
        let g = Float(data[idx + 1]) / 255.0
        let b = Float(data[idx + 2]) / 255.0
        return (r + g + b) / 3.0
    }
    
    private static func defaultAnalysis() -> ImageAnalysis {
        return ImageAnalysis(
            width: 1,
            height: 1,
            averageColor: SIMD3<Float>(0.5, 0.5, 0.5),
            contrast: 0.5,
            brightness: 0.5,
            pixelDensity: 0.5,
            complexity: 5,
            dominantColors: [],
            colorVariance: 0.5,
            edgeDensity: 0.3,
            saturation: 0.5
        )
    }
}
