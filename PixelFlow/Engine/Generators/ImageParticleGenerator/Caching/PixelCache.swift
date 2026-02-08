//
//  PixelCache 2.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import CoreGraphics
import Foundation
import simd

final class PixelCache {
    
    enum ByteOrder {
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
    let width: Int
    let height: Int
    let bytesPerRow: Int
    let byteOrder: ByteOrder
    let dataCount: Int
    
    private let backingData: Data
    private let accessLock = NSLock()
    
#if DEBUG
    static var debugEnabled = true
#else
    static var debugEnabled = false
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
    
    // MARK: - Safe byte access
    
    func withUnsafeBytes<T>(_ body: (UnsafeRawBufferPointer) throws -> T) rethrows -> T {
        try backingData.withUnsafeBytes(body)
    }
    
    // MARK: - Создание из изображения
    
    static func create(from image: CGImage) throws -> PixelCache {
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
        // Всегда BGRA, поскольку GraphicsUtils.createBitmapContext создает контекст с BGRA порядком
        return .bgra
    }
    
    // MARK: - Получение цвета пикселя
    
    func color(atX x: Int, y: Int) -> SIMD4<Float> {
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
        
        guard let bytes = backingData.withUnsafeBytes({ $0.bindMemory(to: UInt8.self).baseAddress }) else {
            return SIMD4<Float>(0, 0, 0, 1)
        }
        
        // Читаем байты
        let byte0 = Float(bytes[byteIndex]) / 255.0
        let byte1 = Float(bytes[byteIndex + 1]) / 255.0
        let byte2 = Float(bytes[byteIndex + 2]) / 255.0
        let byte3 = Float(bytes[byteIndex + 3]) / 255.0
        
        // Преобразуем в зависимости от порядка байтов
        let result: SIMD4<Float>
        switch byteOrder {
        case .rgba:
            result = SIMD4<Float>(byte0, byte1, byte2, byte3)
        case .bgra:
            result = SIMD4<Float>(byte2, byte1, byte0, byte3)
        case .argb:
            result = SIMD4<Float>(byte1, byte2, byte3, byte0)
        }
        
        // NOT усиливаем альфа — это искажает исходные данные пикселя
        // Правильный подход: использовать реальные значения для сэмплирования,
        // а прозрачность частиц контролировать в рендеринге через ParticleConstants
        
        return result
    }
    
    // MARK: - Получение сырых значений
    
    func rawColor(atX x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
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
        
        guard let bytes = backingData.withUnsafeBytes({ $0.bindMemory(to: UInt8.self).baseAddress }) else {
            return nil
        }
        
        // Читаем байты с учетом порядка байтов
        let byte0 = bytes[byteIndex]
        let byte1 = bytes[byteIndex + 1]
        let byte2 = bytes[byteIndex + 2]
        let byte3 = bytes[byteIndex + 3]
        
        // Преобразуем в зависимости от порядка байтов
        switch byteOrder {
        case .rgba:
            return (byte0, byte1, byte2, byte3)
        case .bgra:
            return (byte2, byte1, byte0, byte3)
        case .argb:
            return (byte1, byte2, byte3, byte0)
        }
    }
    
    // MARK: - Работа с областями
    
    func colors(in rect: CGRect, step: Int = 1) -> [SIMD4<Float>] {
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
    
    func averageColor(in rect: CGRect) -> SIMD4<Float> {
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
            Logger.shared.debug(message)
        }
#endif
    }
    
    func printDebugInfo() {
        guard PixelCache.debugEnabled else { return }
        
        Logger.shared.debug("=== PixelCache Debug Information ===")
        Logger.shared.debug("Размеры: \(width) x \(height)")
        Logger.shared.debug("Байтов в строке: \(bytesPerRow)")
        Logger.shared.debug("Формат: \(byteOrder.description)")
        Logger.shared.debug("Общий размер данных: \(dataCount) байт")
        
        // Проверяем угловые пиксели
        let corners = [
            (x: 0, y: 0, label: "Верхний левый"),
            (x: width - 1, y: 0, label: "Верхний правый"),
            (x: 0, y: height - 1, label: "Нижний левый"),
            (x: width - 1, y: height - 1, label: "Нижний правый")
        ]
        
        for corner in corners {
            let color = self.color(atX: corner.x, y: corner.y)
            Logger.shared.debug("\(corner.label) (\(corner.x), \(corner.y)): R=\(color.x) G=\(color.y) B=\(color.z) A=\(color.w)")
        }
    }
    
    // MARK: - Валидация
    
    func validate() -> Bool {
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
