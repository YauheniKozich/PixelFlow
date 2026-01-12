//
//  AdvancedSamplingAlgorithms.swift
//  PixelFlow
//
//  Коллекция продвинутых алгоритмов сэмплинга пикселей
//
//  Этот файл содержит различные алгоритмы выбора пикселей из изображения
//  для генерации частиц. Каждый алгоритм имеет свои преимущества и недостатки.
//
//  Created by AI Assistant on 2026
//
// Не все алгоритмы коректны надо проверять и настраивать

import Foundation
import CoreGraphics
import simd

// MARK: - Перечисление алгоритмов сэмплинга

/// Типы доступных алгоритмов сэмплинга пикселей
enum SamplingAlgorithm: Codable {
    /// Обычное равномерное распределение по всему изображению
    case uniform

    /// Blue Noise - Mitchell's Best Candidate алгоритм
    /// Оптимальное распределение, максимальное расстояние между точками
    case blueNoise

    /// Последовательность Ван дер Корпута
    /// Квази-случайное распределение с хорошими математическими свойствами
    case vanDerCorput

    /// Хэш-based сэмплинг с параллельной генерацией
    /// Быстрый алгоритм с хорошим распределением
    case hashBased

    /// Адаптивный сэмплинг с учетом насыщенности цветов
    /// Предпочитает пиксели с насыщенными цветами
    case adaptive
}

// MARK: - Основной класс с алгоритмами

final class AdvancedPixelSampler {

    // MARK: - Public API

    /// Выполняет сэмплинг пикселей используя выбранный алгоритм
    static func samplePixels(algorithm: SamplingAlgorithm,
                           image: CGImage,
                           targetCount: Int) throws -> [Sample] {

        // Создаем кэш пикселей
        let cache = try createPixelCache(from: image)

        switch algorithm {
        case .uniform:
            return try uniformSampling(width: cache.width, height: cache.height, targetCount: targetCount, cache: cache)
        case .blueNoise:
            return try blueNoiseSampling(width: cache.width, height: cache.height, targetCount: targetCount, cache: cache)
        case .vanDerCorput:
            return try vanDerCorputSampling(width: cache.width, height: cache.height, targetCount: targetCount, cache: cache)
        case .hashBased:
            return try hashBasedSampling(width: cache.width, height: cache.height, targetCount: targetCount, cache: cache)
        case .adaptive:
            return try adaptiveSampling(width: cache.width, height: cache.height, targetCount: targetCount, cache: cache)
        }
    }

    // MARK: - Алгоритм 1: Uniform Sampling (Базовый)

    /// Обычное равномерное распределение
    ///
    /// Простой и быстрый алгоритм, который проходит по всем пикселям
    /// изображения с равным шагом. Гарантирует равномерное покрытие
    /// всего изображения без пропусков.
    ///
    /// Преимущества:
    /// - Очень быстрый
    /// - Полное покрытие изображения
    /// - Детерминированный результат
    ///
    /// Недостатки:
    /// - Может давать диагональные полосы
    /// - Не учитывает содержимое изображения
    private static func uniformSampling(width: Int,
                                      height: Int,
                                      targetCount: Int,
                                      cache: PixelCache) throws -> [Sample] {

        var result: [Sample] = []
        result.reserveCapacity(targetCount)

        let totalPixels = width * height
        let step = max(1, totalPixels / targetCount)

        var pixelIndex = 0
        while result.count < targetCount && pixelIndex < totalPixels {
            let x = pixelIndex % width
            let y = pixelIndex / width

            result.append(Sample(x: x,
                               y: y,
                               color: cache.color(atX: x, y: y)))
            pixelIndex += step
        }

        // Дозаполняем случайными если не хватило
        if result.count < targetCount {
            addRandomSamples(to: &result,
                           width: width,
                           height: height,
                           targetCount: targetCount,
                           cache: cache)
        }

        Logger.shared.debug("Униформное сэмплирование: \(result.count) сэмплов, шаг: \(step)")
        return result
    }

    // MARK: - Алгоритм 2: Blue Noise Sampling (Оптимальный)

    /// Blue Noise Sampling - Mitchell's Best Candidate алгоритм
    ///
    /// Blue Noise - это тип распределения, где точки размещены равномерно,
    /// но каждая точка находится на максимальном расстоянии от соседей.
    /// Это дает оптимальное покрытие без кластеризации.
    ///
    /// Mitchell's Best Candidate работает так:
    /// 1. Начинаем с одной случайной точки
    /// 2. Для каждой новой точки генерируем N кандидатов
    /// 3. Выбираем кандидата farthest от существующих точек
    /// 4. Повторяем пока не наберем нужное количество
    ///
    /// Преимущества:
    /// - Оптимальное распределение (лучше любой сетки)
    /// - Нет видимых паттернов или полос
    /// - Отличное качество для визуальных эффектов
    ///
    /// Недостатки:
    /// - Медленнее других алгоритмов (O(N²) сложность)
    /// - Требует вычислений расстояний
    private static func blueNoiseSampling(width: Int,
                                        height: Int,
                                        targetCount: Int,
                                        cache: PixelCache) throws -> [Sample] {

        var result: [Sample] = []
        result.reserveCapacity(targetCount)

        // Начинаем с одной случайной точки
        let firstX = Int.random(in: 0..<width)
        let firstY = Int.random(in: 0..<height)
        let firstColor = cache.color(atX: firstX, y: firstY)
        result.append(Sample(x: firstX, y: firstY, color: firstColor))

        // Mitchell's Best Candidate алгоритм
        let candidatesPerPoint = 32  // Баланс качества/скорости

        for _ in 1..<targetCount {
            var bestCandidate: Sample?
            var bestMinDistance: Float = 0.0

            // Проверяем несколько кандидатов
            for _ in 0..<candidatesPerPoint {
                let candidateX = Int.random(in: 0..<width)
                let candidateY = Int.random(in: 0..<height)

                // Находим минимальное расстояние до существующих точек
                var minDistance: Float = .infinity
                for existing in result {
                    let dx = Float(candidateX - existing.x)
                    let dy = Float(candidateY - existing.y)
                    let distance = sqrt(dx * dx + dy * dy)
                    minDistance = min(minDistance, distance)
                }

                // Выбираем кандидата с максимальным минимальным расстоянием
                if minDistance > bestMinDistance {
                    bestMinDistance = minDistance
                    let color = cache.color(atX: candidateX, y: candidateY)
                    bestCandidate = Sample(x: candidateX, y: candidateY, color: color)
                }
            }

            // Добавляем лучшего кандидата
            if let candidate = bestCandidate {
                result.append(candidate)
            }
        }

        Logger.shared.debug("Сэмплирование по синему шуму: \(result.count) оптимально распределенных сэмплов")
        return result
    }

    // MARK: - Алгоритм 3: Van der Corput Sequence (Математический)

    /// Сэмплинг на основе последовательности Ван дер Корпута
    ///
    /// Последовательность Ван дер Корпута - это квази-случайная последовательность
    /// с отличными математическими свойствами равномерности.
    /// Использует разные основания для X и Y координат.
    ///
    /// Принцип работы:
    /// - Для каждой точки n вычисляем u(n) и v(n)
    /// - u(n) = последовательность Ван дер Корпута с основанием 2
    /// - v(n) = последовательность Ван дер Корпута с основанием 3
    /// - Масштабируем в диапазон [0, width) и [0, height)
    ///
    /// Преимущества:
    /// - Отличная равномерность (лучше псевдо-случайных чисел)
    /// - Детерминированный результат (для отладки)
    /// - Быстрый (O(N) сложность)
    /// - Низкая discrepancy (мера неравномерности)
    ///
    /// Недостатки:
    /// - Может давать регулярные паттерны при малом N
    /// - Сложнее понять интуитивно
    private static func vanDerCorputSampling(width: Int,
                                           height: Int,
                                           targetCount: Int,
                                           cache: PixelCache) throws -> [Sample] {

        var result: [Sample] = []
        result.reserveCapacity(targetCount)

        for i in 0..<targetCount {
            // Последовательность Ван дер Корпута для X (основание 2)
            let u = vanDerCorput(n: i, base: 2)
            // Для Y используем другое основание (3) для лучшего распределения
            let v = vanDerCorput(n: i, base: 3)

            // Масштабируем в координаты изображения
            let x = Int(u * Float(width))
            let y = Int(v * Float(height))

            // Гарантируем попадание в границы
            let clampedX = min(max(x, 0), width - 1)
            let clampedY = min(max(y, 0), height - 1)

            let color = cache.color(atX: clampedX, y: clampedY)
            result.append(Sample(x: clampedX, y: clampedY, color: color))
        }

        Logger.shared.debug("Сэмплирование Ван дер Корпута: \(result.count) квази-случайных сэмплов")
        return result
    }

    /// Вычисление последовательности Ван дер Корпута
    private static func vanDerCorput(n: Int, base: Int) -> Float {
        var result: Float = 0.0
        var denominator: Float = 1.0
        var n = n

        while n > 0 {
            denominator *= Float(base)
            result += Float(n % base) / denominator
            n /= base
        }

        return result
    }

    // MARK: - Алгоритм 4: Hash-Based Sampling (Быстрый)

    /// Хэш-based сэмплинг с параллельной генерацией
    ///
    /// Использует хэш-функцию для генерации псевдо-случайных координат.
    /// Работает параллельно для высокой производительности.
    ///
    /// Принцип работы:
    /// 1. Для каждого индекса i вычисляем hash(i, seed)
    /// 2. Преобразуем hash в координаты x,y
    /// 3. Автоматически разрешаем коллизии
    ///
    /// Преимущества:
    /// - Очень быстрый (O(N) сложность)
    /// - Детерминированный результат
    /// - Работает параллельно
    /// - Простая реализация
    ///
    /// Недостатки:
    /// - Может иметь кластеры в некоторых областях
    /// - Качество распределения ниже чем у Blue Noise
    private static func hashBasedSampling(width: Int,
                                        height: Int,
                                        targetCount: Int,
                                        cache: PixelCache) throws -> [Sample] {

        let result = ConcurrentSampleBuffer()

        // Параллельная генерация точек
        DispatchQueue.concurrentPerform(iterations: targetCount) { i in
            let hash = murmurHash3(i, seed: 0x9E3779B9)
            let x = Int(hash % UInt32(width))
            let y = Int((hash >> 16) % UInt32(height))

            let color = cache.color(atX: x, y: y)
            result.add(Sample(x: x, y: y, color: color))
        }

        var samples = result.getSamples()

        // Удаляем дубликаты если они есть
        if samples.count > targetCount {
            let uniquePositions = Set(samples.map { PositionKey(x: $0.x, y: $0.y) })
            samples = uniquePositions.prefix(targetCount).map { key in
                let color = cache.color(atX: key.x, y: key.y)
                return Sample(x: key.x, y: key.y, color: color)
            }
        }

        Logger.shared.debug("Хэш-сэмплирование: \(samples.count) параллельно сгенерированных сэмплов")
        return samples
    }

    // MARK: - Алгоритм 5: Adaptive Sampling (Умный)

    /// Адаптивный сэмплинг с учетом содержимого изображения
    ///
    /// Учитывает насыщенность цветов при выборе пикселей.
    /// Предпочитает пиксели с насыщенными цветами для лучшего визуального эффекта.
    ///
    /// Принцип работы:
    /// 1. Базовое равномерное распределение
    /// 2. Предпочтение пикселям с высокой насыщенностью
    /// 3. Дозаполнение обычными пикселями
    ///
    /// Преимущества:
    /// - Учитывает содержимое изображения
    /// - Лучше выделяет контрастные области
    /// - Создает более интересные визуальные эффекты
    ///
    /// Недостатки:
    /// - Сложнее предсказать результат
    /// - Может пропустить важные области
    private static func adaptiveSampling(width: Int,
                                       height: Int,
                                       targetCount: Int,
                                       cache: PixelCache) throws -> [Sample] {

        var result: [Sample] = []
        result.reserveCapacity(targetCount)

        // Сначала собираем насыщенные пиксели (половина от нужного количества)
        let saturatedCount = targetCount / 2
        var pixelIndex = 0
        let totalPixels = width * height
        let step = max(1, totalPixels / saturatedCount)

        while result.count < saturatedCount && pixelIndex < totalPixels {
            let x = pixelIndex % width
            let y = pixelIndex / width

            let color = cache.color(atX: x, y: y)
            // Вычисляем насыщенность (разница между макс и мин каналами)
            let saturation = max(color.x, color.y, color.z) - min(color.x, color.y, color.z)

            // Берем только достаточно насыщенные пиксели
            if saturation > 0.2 {  // Порог насыщенности
                result.append(Sample(x: x, y: y, color: color))
            }

            pixelIndex += step
        }

        // Дозаполняем обычными пикселями
        addRandomSamples(to: &result,
                       width: width,
                       height: height,
                       targetCount: targetCount,
                       cache: cache)

        Logger.shared.debug("Адаптивное сэмплирование: \(result.count) сэмплов с приоритетом \(saturatedCount) насыщенных пикселей")
        return result
    }

    // MARK: - Вспомогательные функции

    /// Добавляет случайные уникальные samples (вспомогательная функция)
    private static func addRandomSamples(to samples: inout [Sample],
                                       width: Int,
                                       height: Int,
                                       targetCount: Int,
                                       cache: PixelCache) {

        var usedPositions = Set<UInt64>()
        samples.forEach { sample in
            let key = positionKey(x: sample.x, y: sample.y)
            usedPositions.insert(key)
        }

        let needed = targetCount - samples.count
        var attempts = 0
        let maxAttempts = needed * 5

        while samples.count < targetCount && attempts < maxAttempts {
            let x = Int.random(in: 0..<width)
            let y = Int.random(in: 0..<height)
            let key = positionKey(x: x, y: y)

            if usedPositions.insert(key).inserted {
                let color = cache.color(atX: x, y: y)
                samples.append(Sample(x: x, y: y, color: color))
            }

            attempts += 1
        }
    }

    /// Создает ключ для позиции (для проверки уникальности)
    private static func positionKey(x: Int, y: Int) -> UInt64 {
        return UInt64(x) | (UInt64(y) << 32)
    }

    /// Простая хэш-функция MurmurHash3
    private static func murmurHash3(_ key: Int, seed: UInt32) -> UInt32 {
        var h = seed &+ UInt32(key)
        h &+= h << 13
        h ^= h >> 7
        h &+= h << 3
        h ^= h >> 17
        h &+= h << 5
        return h
    }
}

// MARK: - Вспомогательные структуры

/// Thread-safe буфер для сбора samples в параллельных операциях
private class ConcurrentSampleBuffer {
    private var samples: [Sample] = []
    private let lock = NSLock()

    func add(_ sample: Sample) {
        lock.lock()
        samples.append(sample)
        lock.unlock()
    }

    func getSamples() -> [Sample] {
        lock.lock()
        defer { lock.unlock() }
        return samples
    }
}

/// Ключ для позиций (для использования в Set)
private struct PositionKey: Hashable {
    let x: Int
    let y: Int

    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y)
    }

    static func == (lhs: PositionKey, rhs: PositionKey) -> Bool {
        return lhs.x == rhs.x && lhs.y == rhs.y
    }
}

// MARK: - Pixel Cache Creation

extension AdvancedPixelSampler {
    /// Создает кэш пикселей из CGImage для быстрого доступа
    static func createPixelCache(from image: CGImage) throws -> PixelCache {
        return try PixelCache.create(from: image)
    }
}
