//
//  PixelCacheHelper.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import Foundation
import CoreGraphics
import simd

// MARK: - PixelCacheHelper

/// Вспомогательные функции для удобного доступа к пикселям,
/// подсчёта яркости/насыщенности и работы с соседями.
///
/// Всё построено вокруг `PixelCache`, которое безопасно отдаёт байты
/// через `withUnsafeBytes` без утечки указателя.
enum PixelCacheHelper {

    // MARK: - Константы
    
    enum Constants {
        static let bytesPerPixel: Int = 4
        static let alphaThreshold: Float = 0.1
        static let lowAlphaThreshold: Float = 0.05
        static let neighborRange = -1...1
    }

    // MARK: - Вспомогательные типы
    
    struct PixelCoordinate: Hashable {
        let x: Int
        let y: Int
    }

    // MARK: - Создание кеша

    static func createPixelCache(from image: CGImage) throws -> PixelCache {
        try PixelCache.create(from: image)
    }

    // MARK: - Чтение одного пикселя
    /// Возвращает нормализованные компоненты (0…1) или `nil`,
    /// если координаты выходят за границы кеша.
    static func getPixelData(atX x: Int,
                             y: Int,
                             from cache: PixelCache) -> (r: Float, g: Float,
                                                        b: Float, a: Float)? {

        // проверка границ
        guard x >= 0, x < cache.width,
              y >= 0, y < cache.height else {
            return nil
        }

        // правильный способ
        // `PixelCache.color(atX:y:)` уже знает о порядке байтов и выравнивании.
        let rgba = cache.color(atX: x, y: y)
        return (r: rgba.x, g: rgba.y, b: rgba.z, a: rgba.w)
    }

    // MARK: - Соседи
    /// Возвращает массив цветов 8‑ми соседних пикселей (без центрального).
    static func getNeighborPixels(atX x: Int,
                                  y: Int,
                                  from cache: PixelCache) -> [(r: Float, g: Float,
                                                             b: Float, a: Float)] {
        var result: [(r: Float, g: Float, b: Float, a: Float)] = []

        for dy in Constants.neighborRange {
            for dx in Constants.neighborRange {
                // пропускаем сам пиксель
                guard !(dx == 0 && dy == 0) else { continue }

                let nx = x + dx
                let ny = y + dy

                // проверка границ
                guard nx >= 0, nx < cache.width,
                      ny >= 0, ny < cache.height else { continue }

                // используем уже готовый метод – быстрый и корректный
                let c = cache.color(atX: nx, y: ny)
                result.append((r: c.x, g: c.y, b: c.z, a: c.w))
            }
        }
        return result
    }

    /// SIMD‑вариант – возвращает массив `SIMD4<Float>`.
    static func getNeighborPixelsSIMD(atX x: Int,
                                      y: Int,
                                      from cache: PixelCache) -> [SIMD4<Float>] {
        var result: [SIMD4<Float>] = []

        for dy in Constants.neighborRange {
            for dx in Constants.neighborRange {
                guard !(dx == 0 && dy == 0) else { continue }

                let nx = x + dx
                let ny = y + dy

                guard nx >= 0, nx < cache.width,
                      ny >= 0, ny < cache.height else { continue }

                result.append(cache.color(atX: nx, y: ny))
            }
        }
        return result
    }

    // MARK: - Яркость / Насыщенность
 
    static func getPixelBrightness(atX x: Int,
                                   y: Int,
                                   from cache: PixelCache) -> Float? {
        guard let c = getPixelData(atX: x, y: y, from: cache) else { return nil }
        // Формула ITU‑R BT.601
        return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
    }

    static func getPixelSaturation(atX x: Int,
                                   y: Int,
                                   from cache: PixelCache) -> Float? {
        guard let c = getPixelData(atX: x, y: y, from: cache) else { return nil }

        let maxV = max(c.r, max(c.g, c.b))
        let minV = min(c.r, min(c.g, c.b))

        guard maxV > 0 else { return 0 }
        return (maxV - minV) / maxV
    }

    // MARK: - Прозрачность
 
    static func isTransparentPixel(atX x: Int,
                                   y: Int,
                                   from cache: PixelCache) -> Bool {
        guard let c = getPixelData(atX: x, y: y, from: cache) else { return true }
        return c.a < Constants.alphaThreshold
    }

    static func isLowAlphaPixel(atX x: Int,
                                y: Int,
                                from cache: PixelCache) -> Bool {
        guard let c = getPixelData(atX: x, y: y, from: cache) else { return true }
        return c.a < Constants.lowAlphaThreshold
    }

    // MARK: - Хеш‑ключи позиции

    @inline(__always)
    static func positionKey(_ x: Int, _ y: Int) -> UInt64 {
        (UInt64(x) << 32) | UInt64(y)
    }

    static func positionFromKey(_ key: UInt64) -> (x: Int, y: Int) {
        let x = Int((key >> 32) & 0xFFFFFFFF)
        let y = Int(key & 0xFFFFFFFF)
        return (x, y)
    }

    // MARK: - Работа с набором сэмплов

    static func usedPositions(from samples: [Sample]) -> Set<UInt64> {
        var set = Set<UInt64>(minimumCapacity: samples.count)
        for s in samples { set.insert(positionKey(s.x, s.y)) }
        return set
    }

    // MARK: - Валидация кеша

    static func validatePixelCache(_ cache: PixelCache,
                                  atPoints points: [(x: Int, y: Int)]) -> Bool {

        for (idx, p) in points.enumerated() {
            guard p.x >= 0, p.x < cache.width,
                  p.y >= 0, p.y < cache.height else {
                Logger.shared.warning("Точка \(idx): [\(p.x),\(p.y)] выходит за границы")
                return false
            }

            let c = cache.color(atX: p.x, y: p.y)
            // проверка диапазона 0…1
            guard (0...1).contains(c.x),
                  (0...1).contains(c.y),
                  (0...1).contains(c.z),
                  (0...1).contains(c.w) else {
                Logger.shared.warning("Точка \(idx): неверные компоненты \(c)")
                return false
            }
        }
        return true
    }

    // MARK: - Сравнение разных способов доступа

    static func comparePixelAccessMethods(atX x: Int,
                                          y: Int,
                                          from cache: PixelCache) {

        // Прямой доступ к сырому буферу (для отладки)
        let i = y * cache.bytesPerRow + x * Constants.bytesPerPixel
        if i + 3 < cache.dataCount {
            cache.withUnsafeBytes { rawBuffer in
                guard let base = rawBuffer.bindMemory(to: UInt8.self).baseAddress else { return }
                _ = (base[i], base[i+1], base[i+2], base[i+3])
            }
        }
    }
}
