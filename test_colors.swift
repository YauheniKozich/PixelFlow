#!/usr/bin/env swift

import Foundation
import CoreGraphics
import simd

// Тестовый скрипт для проверки извлечения цветов из PixelCache
print("Тестируем извлечение цветов из PixelCache...")

// Создаем тестовое изображение 10x10 с градиентом
let width = 10
let height = 10

guard let context = CGContext(data: nil,
                             width: width,
                             height: height,
                             bitsPerComponent: 8,
                             bytesPerRow: 0,
                             space: CGColorSpaceCreateDeviceRGB(),
                             bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
    print("Не удалось создать контекст")
    exit(1)
}

// Заполняем градиентом
for y in 0..<height {
    for x in 0..<width {
        let r = Float(x) / Float(width - 1)  // Красный градиент по X
        let g = Float(y) / Float(height - 1) // Зеленый градиент по Y
        let b = 0.5                           // Синий постоянный
        let a = 1.0

        context.setFillColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(a))
        context.fill(CGRect(x: x, y: y, width: 1, height: 1))
    }
}

guard let image = context.makeImage() else {
    print("Не удалось создать изображение")
    exit(1)
}

// Создаем PixelCache
do {
    let cache = try PixelCache.create(from: image)

    print("Размер изображения: \(cache.width) x \(cache.height)")
    print("Bytes per row: \(cache.bytesPerRow)")

    // Тестируем извлечение цветов в разных точках
    let testPoints = [
        (x: 0, y: 0, expected: "Красный: 0.0, Зеленый: 0.0"),
        (x: 9, y: 0, expected: "Красный: 1.0, Зеленый: 0.0"),
        (x: 0, y: 9, expected: "Красный: 0.0, Зеленый: 1.0"),
        (x: 9, y: 9, expected: "Красный: 1.0, Зеленый: 1.0"),
        (x: 4, y: 4, expected: "Красный: 0.5, Зеленый: 0.5")
    ]

    for (x, y, expected) in testPoints {
        let color = cache.color(atX: x, y: y)
        print("Точка [\(x),\(y)]: R=\(String(format: "%.3f", color.x)), G=\(String(format: "%.3f", color.y)), B=\(String(format: "%.3f", color.z)), A=\(String(format: "%.3f", color.w)) - \(expected)")
    }

    print("Тест завершен успешно!")

} catch {
    print("Ошибка при создании PixelCache: \(error)")
    exit(1)
}