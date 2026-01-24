//
//  GraphicsUtils.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import CoreGraphics
import Foundation

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
        // Явно указываем BGRA порядок для совместимости с Metal (iOS little-endian)
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        
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
            
            // Очищаем контекст белым цветом чтобы избежать артефактов
            if let whiteColor = CGColor(colorSpace: colorSpace, components: [1.0, 1.0, 1.0, 1.0]) {
                context.setFillColor(whiteColor)
                context.fill(CGRect(x: 0, y: 0, width: width, height: height))
            }
        } else {
            Logger.shared.error("Не удалось создать CGContext")
        }
        
        return context
    }
}
