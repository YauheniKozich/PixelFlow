//
//  PixelCache 2.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import CoreGraphics
import Foundation
import simd

public final class PixelCache {
    
    public enum ByteOrder {
        case rgba
        case bgra
        case argb
        
        var description: String {
            switch self {
            case .rgba: return "RGBA"
            case .bgra: return "BGRA"
            case .argb: return "ARGB"
            }
        }
    }
    
    // Основные свойства
    public let width: Int
    public let height: Int
    public let bytesPerRow: Int
    public let byteOrder: ByteOrder
    public let dataCount: Int
    
    // Доступ к данным
    public var dataPointer: UnsafeMutableRawPointer {
        return UnsafeMutableRawPointer(mutating: backingData.withUnsafeBytes { $0.baseAddress! })
    }
    
    // Приватные свойства
    private let backingData: Data
    private let accessLock = NSLock()
    
    #if DEBUG
    public static var debugEnabled = true
    #else
    public static var debugEnabled = false
    #endif
    
    // MARK: - Инициализация
    
    private init(width: Int,
                 height: Int,
                 bytesPerRow: Int,
                 byteOrder: ByteOrder,
                 backingData: Data) {
        
        self.width = width
        self.height = height
        self.bytesPerRow = bytesPerRow
        self.byteOrder = byteOrder
        self.backingData = backingData
        self.dataCount = backingData.count
        
        debugLog("[PixelCache] создан: \(width)x\(height), stride=\(bytesPerRow), формат=\(byteOrder.description)")
    }
    
    // MARK: - Создание из изображения
    
    public static func create(from image: CGImage) throws -> PixelCache {
        guard image.width > 0 && image.height > 0 else {
            throw GeneratorError.invalidImage
        }
        
        let width = image.width
        let height = image.height
        
        // Создаем контекст для работы с пикселями
        guard let context = GraphicsUtils.createBitmapContext(width: width, height: height) else {
            throw GeneratorError.samplingFailed(reason: "Не удалось создать графический контекст")
        }
        
        // Рисуем изображение в контекст
        let rect = CGRect(x: 0, y: 0, width: width, height: height)
        context.draw(image, in: rect)
        
        // Получаем данные из контекста
        guard let rawData = context.data else {
            throw GeneratorError.samplingFailed(reason: "Контекст не содержит данных")
        }
        
        let stride = context.bytesPerRow
        let bufferSize = stride * height
        
        // Копируем данные в безопасный буфер
        let pixelData = Data(bytes: rawData, count: bufferSize)
        
        // Определяем порядок байтов
        let byteOrder = determineByteOrder(from: context)
        
        // Создаем кеш
        let cache = PixelCache(width: width,
                              height: height,
                              bytesPerRow: stride,
                              byteOrder: byteOrder,
                              backingData: pixelData)
        
        // Отладочная информация
        if debugEnabled {
            cache.printDebugInfo()
        }
        
        return cache
    }
    
    // MARK: - Определение порядка байтов
    
    private static func determineByteOrder(from context: CGContext) -> ByteOrder {
        let bitmapInfo = context.bitmapInfo
        
        // Проверяем явные флаги порядка байтов
        if bitmapInfo.contains(.byteOrder32Little) {
            return .bgra
        }
        if bitmapInfo.contains(.byteOrder32Big) {
            return .rgba
        }
        
        // Если флаги не установлены, ориентируемся на расположение альфа-канала
        switch context.alphaInfo {
        case .premultipliedLast, .last, .noneSkipLast:
            return .rgba
        case .premultipliedFirst, .first, .noneSkipFirst:
            return .bgra
        default:
            // По умолчанию для iOS/Mac используем BGRA
            return .bgra
        }
    }
    
    // MARK: - Получение цвета пикселя
    
    public func color(atX x: Int, y: Int) -> SIMD4<Float> {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            fatalError("Координаты пикселя вне границ: (\(x), \(y))")
        }
        
        // Вычисляем позицию в буфере
        let rowOffset = y * bytesPerRow
        let pixelOffset = x * 4
        let byteIndex = rowOffset + pixelOffset
        
        guard byteIndex + 3 < dataCount else {
            return SIMD4<Float>(0, 0, 0, 1)
        }
        
        // Блокируем доступ для потокобезопасности
        accessLock.lock()
        defer { accessLock.unlock() }
        
        let bytes = backingData.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
        
        // Читаем байты
        let byte0 = Float(bytes[byteIndex]) / 255.0
        let byte1 = Float(bytes[byteIndex + 1]) / 255.0
        let byte2 = Float(bytes[byteIndex + 2]) / 255.0
        let byte3 = Float(bytes[byteIndex + 3]) / 255.0
        
        // Преобразуем в зависимости от порядка байтов
        switch byteOrder {
        case .rgba:
            return SIMD4<Float>(byte0, byte1, byte2, byte3)
        case .bgra:
            return SIMD4<Float>(byte2, byte1, byte0, byte3)
        case .argb:
            return SIMD4<Float>(byte1, byte2, byte3, byte0)
        }
    }
    
    // MARK: - Получение сырых значений
    
    public func rawColor(atX x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return nil
        }
        
        let rowOffset = y * bytesPerRow
        let pixelOffset = x * 4
        let byteIndex = rowOffset + pixelOffset
        
        guard byteIndex + 3 < dataCount else {
            return nil
        }
        
        accessLock.lock()
        defer { accessLock.unlock() }
        
        let bytes = backingData.withUnsafeBytes { $0.bindMemory(to: UInt8.self).baseAddress! }
        
        let r = bytes[byteIndex]
        let g = bytes[byteIndex + 1]
        let b = bytes[byteIndex + 2]
        let a = bytes[byteIndex + 3]
        
        return (r, g, b, a)
    }
    
    // MARK: - Работа с областями
    
    public func colors(in rect: CGRect, step: Int = 1) -> [SIMD4<Float>] {
        // Ограничиваем прямоугольник границами изображения
        let minX = max(0, Int(rect.minX.rounded(.down)))
        let maxX = min(width - 1, Int(rect.maxX.rounded(.down)))
        let minY = max(0, Int(rect.minY.rounded(.down)))
        let maxY = min(height - 1, Int(rect.maxY.rounded(.down)))
        
        guard minX <= maxX && minY <= maxY else {
            return []
        }
        
        var result: [SIMD4<Float>] = []
        
        // Предвыделяем память для оптимизации
        let estimatedCount = ((maxY - minY) / step + 1) * ((maxX - minX) / step + 1)
        result.reserveCapacity(estimatedCount)
        
        // Собираем цвета с заданным шагом
        for y in stride(from: minY, through: maxY, by: step) {
            for x in stride(from: minX, through: maxX, by: step) {
                result.append(color(atX: x, y: y))
            }
        }
        
        return result
    }
    
    public func averageColor(in rect: CGRect) -> SIMD4<Float> {
        let colors = self.colors(in: rect, step: 2)
        guard !colors.isEmpty else {
            return SIMD4<Float>(0, 0, 0, 1)
        }
        
        var sum = SIMD4<Float>(0, 0, 0, 0)
        for color in colors {
            sum += color
        }
        
        return sum / Float(colors.count)
    }
    
    // MARK: - Отладочные методы
    
    private func debugLog(_ message: String) {
        #if DEBUG
        if PixelCache.debugEnabled {
            print(message)
        }
        #endif
    }
    
    public func printDebugInfo() {
        guard PixelCache.debugEnabled else { return }
        
        print("\n=== PixelCache Debug Information ===")
        print("Размеры: \(width) x \(height)")
        print("Байтов в строке: \(bytesPerRow)")
        print("Формат: \(byteOrder.description)")
        print("Общий размер данных: \(dataCount) байт")
        
        // Проверяем угловые пиксели
        let corners = [
            (x: 0, y: 0, label: "Верхний левый"),
            (x: width - 1, y: 0, label: "Верхний правый"),
            (x: 0, y: height - 1, label: "Нижний левый"),
            (x: width - 1, y: height - 1, label: "Нижний правый")
        ]
        
        for corner in corners {
            let color = self.color(atX: corner.x, y: corner.y)
            print("\(corner.label) (\(corner.x), \(corner.y)): R=\(color.x) G=\(color.y) B=\(color.z) A=\(color.w)")
        }
    }
    
    // MARK: - Валидация
    
    public func validate() -> Bool {
        // Проверяем базовые параметры
        guard width > 0 && height > 0 else {
            return false
        }
        
        // Проверяем, что данных достаточно
        let requiredBytes = (height - 1) * bytesPerRow + width * 4
        guard dataCount >= requiredBytes else {
            return false
        }
        
        // Проверяем несколько случайных пикселей
        for _ in 0..<5 {
            let x = Int.random(in: 0..<width)
            let y = Int.random(in: 0..<height)
            let color = self.color(atX: x, y: y)
            
            // Проверяем, что значения в допустимом диапазоне
            guard (0...1).contains(color.x),
                  (0...1).contains(color.y),
                  (0...1).contains(color.z),
                  (0...1).contains(color.w) else {
                return false
            }
        }
        
        return true
    }
}
