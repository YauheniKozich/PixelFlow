//
//  PixelSampling.swift
//  PixelFlow
//
//  УМНЫЙ СЭМПЛИНГ ПИКСЕЛЕЙ С УЧЕТОМ ВАЖНОСТИ
//  - Анализ контраста и соседей
//  - Взвешенный выбор по важности
//  - Адаптивная плотность
//
//  ПРИМЕЧАНИЕ: Этот файл содержит альтернативную реализацию сэмплинга.
//  Основная реализация находится в PixelSampler.swift.
//  Этот код может быть полезен для тестирования или как альтернативный подход.
//

import CoreGraphics
import CoreImage
import simd

// MARK: Хранилище пиксельных данных использует PixelCache из GraphicsUtils

// MARK: Основной код генерации образцов (переименован в `performPixelSampling`)

extension ImageParticleGenerator {

    
    //  Константы, используемые в алгоритме
    private enum Constants {
        static let bytesPerPixel: Int          = 4
        static let alphaThreshold: Float      = 0.1
        static let lowAlphaThreshold: Float   = 0.05
        static let minImportanceThreshold: Float = 0.01
        static let maxAttemptsMultiplier: Int  = 10
        static let neighborRange = -1...1
    }

    //  Публичный API – вызывается из ParticleGenerator
    static func performPixelSampling(
        image: CGImage,
        desiredCount: Int,
        dominantColors: [SIMD3<Float>]
    ) throws -> [Sample] {

        // Валидация
        guard desiredCount > 0 else {
            Logger.shared.warning("Желаемое количество = 0 → пустой набор сэмплов")
            return []
        }
        guard image.width > 0, image.height > 0 else {
            throw GeneratorError.invalidImage
        }

        // Чтение пикселей с правильным stride
        guard let cache = preparePixelCache(from: image) else {
            throw GeneratorError.samplingFailed(reason: "Unable to read pixel data")
        }

        let width  = cache.width
        let height = cache.height

        // Параметры сканирования (stride)
        // Число точек, которые будем проверять – меньший stride → быстрее, но хуже качество
        let strideX = max(1, width  / 512)
        let strideY = max(1, height / 512)

        Logger.shared.debug("""
            Сканирование изображения \(width)x\(height) с шагом \(strideX)x\(strideY)
            Целевые сэмплы: \(desiredCount), доминирующие цвета: \(dominantColors.count)
            """)

        // Сбор «важных» пикселей
        var candidates = gatherImportantPixels(
            cache: cache,
            width: width,
            height: height,
            strideX: strideX,
            strideY: strideY,
            dominantColors: dominantColors
        )
        Logger.shared.debug("Найдено \(candidates.count) важных пикселей")

        // При необходимости – добавляем резервные
        let minImportant = max(desiredCount / 4, 10)
        if candidates.count < minImportant {
            Logger.shared.warning("Недостаточно важных пикселей (\(candidates.count)), добавляем fallback")
            let needed = desiredCount - candidates.count
            let fallback = gatherFallbackPixels(
                cache: cache,
                width: width,
                height: height,
                neededCount: needed
            )
            candidates.append(contentsOf: fallback)
        }

        // Если всё ещё мало – берём все
        if candidates.count <= desiredCount {
            let samples = candidates.map { Sample(x: $0.x, y: $0.y, color: $0.color) }
            Logger.shared.info("Возврат \(samples.count) сэмплов (все найденные)")
            return samples
        }

        // Сортируем и отбираем
        candidates.sort { $0.importance > $1.importance }

        let finalSamples = selectFinalSamples(
            sortedCandidates: candidates,
            desiredCount: desiredCount,
            cache: cache,
            width: width,
            height: height,
            strideX: strideX,
            strideY: strideY
        )

        logImportanceStats(candidates: candidates)
        Logger.shared.info("Возврат \(finalSamples.count) окончательных сэмплов")
        return finalSamples
    }

    // MARK: Подготовка контекста и получение корректного stride
    
    private static func preparePixelCache(from image: CGImage) -> PixelCache? {
        do {
            return try PixelCache.create(from: image)
        } catch {
            Logger.shared.error("Не удалось создать кэш пикселей: \(error)")
            return nil
        }
    }

    // MARK: Выбор важных пикселей
    
    private static func gatherImportantPixels(
        cache: PixelCache,
        width: Int,
        height: Int,
        strideX: Int,
        strideY: Int,
        dominantColors: [SIMD3<Float>]
    ) -> [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] {

        var candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] = []
        // Предрезервируем память (экономия аллокаций)
        candidates.reserveCapacity((width / strideX) * (height / strideY))

        for y in stride(from: 0, to: height, by: strideY) {
            for x in stride(from: 0, to: width, by: strideX) {

                // Получаем цвет текущего пикселя
                guard let pixel = getPixelData(atX: x, y: y, from: cache) else { continue }
                guard pixel.a > Constants.alphaThreshold else { continue }

                // Соседи (8‑окрестных пикселей)
                let neighbors = getNeighborPixels(atX: x, y: y, from: cache)

                // Вычисление важности
                let importance = calculatePixelImportance(
                    r: pixel.r, g: pixel.g, b: pixel.b, a: pixel.a,
                    neighbors: neighbors,
                    dominantColors: dominantColors
                )

                if importance > Constants.minImportanceThreshold {
                    candidates.append((
                        x: x,
                        y: y,
                        color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
                        importance: importance
                    ))
                }
            }
        }
        return candidates
    }

    // MARK: Резервные пиксели (низкая альфа)

    private static func gatherFallbackPixels(
        cache: PixelCache,
        width: Int,
        height: Int,
        neededCount: Int
    ) -> [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] {

        guard neededCount > 0 else { return [] }

        var fallback: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)] = []
        fallback.reserveCapacity(min(neededCount, width * height))

        // Чем больше шаг – тем быстрее, но хуже покрытие
        let strideX = max(1, width  / 100)
        let strideY = max(1, height / 100)

        outer: for y in stride(from: 0, to: height, by: strideY) {
            for x in stride(from: 0, to: width, by: strideX) {

                guard let pixel = getPixelData(atX: x, y: y, from: cache) else { continue }
                if pixel.a > Constants.lowAlphaThreshold {
                    fallback.append((
                        x: x,
                        y: y,
                        color: SIMD4<Float>(pixel.r, pixel.g, pixel.b, pixel.a),
                        importance: 0.1      // «псевдо‑важность» – будет использована в fallback‑выборке
                    ))
                    if fallback.count >= neededCount { break outer }
                }
            }
        }
        return fallback
    }

    // MARK: Финальный отбор (весовой, случайный, дополнение)

    private static func selectFinalSamples(
        sortedCandidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)],
        desiredCount: Int,
        cache: PixelCache,
        width: Int,
        height: Int,
        strideX: Int,
        strideY: Int
    ) -> [Sample] {

        guard !sortedCandidates.isEmpty else { return [] }

        var result: [Sample] = []
        result.reserveCapacity(desiredCount)

        // Основные (самые важные)
        let baseCount = Int(Float(desiredCount) * 0.6)                // 60 % от всех
        let take = min(baseCount, sortedCandidates.count)
        for i in 0..<take {
            let c = sortedCandidates[i]
            result.append(Sample(x: c.x, y: c.y, color: c.color))
        }

        // Взвешенные случайные
        let bonusCount = desiredCount - result.count
        if bonusCount > 0 && sortedCandidates.count > take {
            let remaining = Array(sortedCandidates[take...])
            result.append(contentsOf: selectWeightedSamples(
                from: remaining,
                count: bonusCount
            ))
        }

        // Если всё ещё не хватает – случайные без повторов
        if result.count < desiredCount {
            let needed = desiredCount - result.count
            let exclude = Set(result.map { PixelCoordinate(x: $0.x, y: $0.y) })
            result.append(contentsOf: selectRandomSamples(
                from: sortedCandidates,
                count: needed,
                exclude: exclude
            ))
        }

        // Обрезаем избыточные
        if result.count > desiredCount {
            result = Array(result.prefix(desiredCount))
        }
        return result
    }

    // MARK: Взвешенный случайный отбор

    private static func selectWeightedSamples(
        from candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)],
        count: Int
    ) -> [Sample] {

        guard count > 0, !candidates.isEmpty else { return [] }

        var samples: [Sample] = []
        samples.reserveCapacity(count)

        let totalImportance = candidates.reduce(0.0) { $0 + $1.importance }
        guard totalImportance > 0 else {
            // Если у всех одинаковая важность – берём обычные случайные
            return selectRandomSamples(from: candidates, count: count, exclude: Set())
        }

        for _ in 0..<count {
            var target = Float.random(in: 0..<totalImportance)
            for cand in candidates {
                target -= cand.importance
                if target <= 0 {
                    samples.append(Sample(x: cand.x, y: cand.y, color: cand.color))
                    break
                }
            }
        }
        return samples
    }

    // MARK: Случайный отбор без повторов

    private static func selectRandomSamples(
        from candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)],
        count: Int,
        exclude: Set<PixelCoordinate>
    ) -> [Sample] {

        guard count > 0, !candidates.isEmpty else { return [] }

        var samples: [Sample] = []
        samples.reserveCapacity(count)

        var attempts = 0
        let maxAttempts = count * Constants.maxAttemptsMultiplier

        while samples.count < count && attempts < maxAttempts {
            guard let cand = candidates.randomElement() else { break }
            let coord = PixelCoordinate(x: cand.x, y: cand.y)
            if !exclude.contains(coord) {
                samples.append(Sample(x: cand.x, y: cand.y, color: cand.color))
            }
            attempts += 1
        }
        return samples
    }

    // MARK: Получение одного пикселя (с учётом stride)

    private static func getPixelData(atX x: Int, y: Int, from cache: PixelCache) -> (r: Float, g: Float, b: Float, a: Float)? {

        guard x >= 0, x < cache.width, y >= 0, y < cache.height else { return nil }

        let i = y * cache.bytesPerRow + x * Constants.bytesPerPixel
        guard i + 3 < cache.data.count else { return nil }

        return (
            r: Float(cache.data[i])     / 255.0,
            g: Float(cache.data[i + 1]) / 255.0,
            b: Float(cache.data[i + 2]) / 255.0,
            a: Float(cache.data[i + 3]) / 255.0
        )
    }

    // MARK: Соседние пиксели (8‑окрест)
    
    private static func getNeighborPixels(atX x: Int, y: Int, from cache: PixelCache) -> [(r: Float, g: Float, b: Float, a: Float)] {

        var neighbors: [(r: Float, g: Float, b: Float, a: Float)] = []

        for dy in Constants.neighborRange {
            for dx in Constants.neighborRange {
                // пропускаем центр
                guard !(dx == 0 && dy == 0) else { continue }

                let nx = x + dx
                let ny = y + dy
                if let p = getPixelData(atX: nx, y: ny, from: cache) {
                    neighbors.append(p)
                }
            }
        }
        return neighbors
    }

    // MARK: Вычисление важности одного пикселя

    private static func calculatePixelImportance(
        r: Float, g: Float, b: Float, a: Float,
        neighbors: [(r: Float, g: Float, b: Float, a: Float)],
        dominantColors: [SIMD3<Float>]
    ) -> Float {

        // Если полностью прозрачный – не учитываем
        guard a > Constants.alphaThreshold else { return 0.0 }

        // Локальный контраст
        let localContrast: Float = {
            guard !neighbors.isEmpty else { return 0.0 }
            var sum: Float = 0
            for n in neighbors {
                let dr = r - n.r
                let dg = g - n.g
                let db = b - n.b
                sum += simd_length(SIMD3<Float>(dr, dg, db))
            }
            return sum / Float(neighbors.count)
        }()

        // Насыщенность (по формуле, аналогичной Hue‑/Saturation)
        let avg = (r + g + b) / 3.0
        let dr = r - avg
        let dg = g - avg
        let db = b - avg
        let saturation = sqrt(dr * dr + dg * dg + db * db)

        // Уникальность относительно доминантных цветов
        let minDistToDominant: Float = {
            guard !dominantColors.isEmpty else { return 1.0 }
            var minDist = Float.greatestFiniteMagnitude
            let cur = SIMD3<Float>(r, g, b)
            for dom in dominantColors {
                let d = simd_distance(cur, dom)
                if d < minDist { minDist = d }
                if minDist < 0.001 { break }    // быстрый exit
            }
            return min(minDist, 1.0)
        }()

        // Взвешивание
        let weights = SIMD3<Float>(0.4, 0.3, 0.3)   // контраст, насыщенность, уникальность
        let factors = SIMD3<Float>(localContrast, saturation, minDistToDominant)
        let importance = simd_dot(weights, factors)

        return max(importance, 0.0)
    }

    // MARK: Логирование статистики важности

    private static func logImportanceStats(
        candidates: [(x: Int, y: Int, color: SIMD4<Float>, importance: Float)]
    ) {
        guard !candidates.isEmpty else {
            Logger.shared.debug("Нет кандидатов – нечего логировать")
            return
        }

        let values = candidates.map { $0.importance }
        let avg = values.reduce(0, +) / Float(values.count)
        let maxImp = values.max() ?? 0
        let minImp = values.min() ?? 0
        Logger.shared.debug("Важность – средн: \(String(format: "%.3f", avg)), макс: \(String(format: "%.3f", maxImp)), мин: \(String(format: "%.3f", minImp))")
    }

    // MARK: Структура координат (для Set‑а)

    private struct PixelCoordinate: Hashable {
        let x: Int
        let y: Int
    }
}
