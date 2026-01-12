//
//  GraphicsUtils.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import CoreGraphics
import Foundation
import simd

// MARK: - Pixel Cache

/// Кэш пиксельных данных для быстрого доступа к цветам пикселей
public struct PixelCache {
    public let data: [UInt8]          // RGBA‑байты
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int       // реальный stride

    /// Возвращает цвет пикселя в диапазоне 0…1.
    public func color(atX x: Int, y: Int) -> SIMD4<Float> {
        precondition(x >= 0 && x < width && y >= 0 && y < height,
                     "Pixel coordinates out of bounds")
        let rowStart = y * bytesPerRow
        let colStart = x * 4
        let i = rowStart + colStart
        return SIMD4<Float>(
            Float(data[i])     / 255.0,
            Float(data[i + 1]) / 255.0,
            Float(data[i + 2]) / 255.0,
            Float(data[i + 3]) / 255.0
        )
    }

    /// Создает PixelCache из CGImage
    public static func create(from image: CGImage) throws -> PixelCache {
        let width  = image.width
        let height = image.height
        guard width > 0 && height > 0 else { throw GeneratorError.invalidImage }

        // Создаем bitmap контекст
        guard let ctx = GraphicsUtils.createBitmapContext(width: width, height: height) else {
            throw GeneratorError.samplingFailed(reason: "Unable to create CGContext")
        }

        // Рисуем изображение в контекст
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        // Получаем реальный stride и сырые байты
        guard let dataPtr = ctx.data else {
            throw GeneratorError.samplingFailed(reason: "CGContext has no pixel data")
        }
        let stride = ctx.bytesPerRow
        let bufferSize = stride * height

        // Копируем в Swift-массив
        let rawData = Data(bytes: dataPtr, count: bufferSize)
        let pixelArray = [UInt8](rawData)

        return PixelCache(
            data: pixelArray,
            width: width,
            height: height,
            bytesPerRow: stride
        )
    }
}

struct GraphicsUtils {
    // Кэш для bytesPerRow чтобы избежать создания тестовых контекстов
    private static let bytesPerRowCache = NSCache<NSNumber, NSNumber>()
    private static let cacheQueue = DispatchQueue(label: "com.aether.graphicsutils.cache")
    
    /// Вычисляет корректный bytesPerRow с учетом выравнивания памяти
    static func bytesPerRow(forWidth width: Int, bitsPerPixel: Int = 32) -> Int {
        // Проверяем кэш
        let cacheKey = NSNumber(value: width)
        if let cached = cacheQueue.sync(execute: { bytesPerRowCache.object(forKey: cacheKey) }) {
            return cached.intValue
        }
        
        let bytesPerPixel = bitsPerPixel / 8
        let baseBytesPerRow = width * bytesPerPixel
        
        // Для Core Graphics выравнивание обычно 16 или 32 байта
        // Создаем минимальный тестовый контекст для определения stride
        var calculatedBytesPerRow = baseBytesPerRow
        if let testContext = CGContext(data: nil,
                                      width: width,
                                      height: 1,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0, // 0 = автоматическое вычисление
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) {
            calculatedBytesPerRow = testContext.bytesPerRow
        } else {
            // Fallback: выравнивание до 16 байт
            let alignment = 16
            calculatedBytesPerRow = (baseBytesPerRow + alignment - 1) / alignment * alignment
        }
        
        // Сохраняем в кэш
        cacheQueue.async {
            bytesPerRowCache.setObject(NSNumber(value: calculatedBytesPerRow), forKey: cacheKey)
        }
        
        return calculatedBytesPerRow
    }
    
    /// Создает CGContext с корректными параметрами
    static func createBitmapContext(width: Int, height: Int) -> CGContext? {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue
        
        let bytesPerRow = bytesPerRow(forWidth: width)
        
        Logger.shared.debug("Создание контекста: ширина=\(width), высота=\(height), рассчитанные bytesPerRow=\(bytesPerRow)")
        
        let context = CGContext(data: nil,
                                width: width,
                                height: height,
                                bitsPerComponent: 8,
                                bytesPerRow: bytesPerRow,
                                space: colorSpace,
                                bitmapInfo: bitmapInfo)
        
        if let context = context {
            Logger.shared.debug("Контекст создан. Фактические bytesPerRow: \(context.bytesPerRow)")
        } else {
            Logger.shared.error("Не удалось создать CGContext")
        }
        
        return context
    }
}
