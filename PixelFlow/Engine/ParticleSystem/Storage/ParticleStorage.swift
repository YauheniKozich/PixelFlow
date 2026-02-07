//
//  ParticleStorage.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Хранилище частиц и управление буферами
//

import Metal
import simd

// MARK: - Pixel Struct

/// Структура исходного пикселя для сборки частиц
struct Pixel {
    var x: Int
    var y: Int
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

/// Хранилище частиц
final class ParticleStorage {
    
    // MARK: - Properties
    var particleBuffer: MTLBuffer?
    public private(set) var particleCount: Int = 0
    
    private let device: MTLDevice
    private let logger: LoggerProtocol
    
    // Размеры экрана для преобразования координат
    private var viewWidth: Float
    private var viewHeight: Float
    
    // Очередь для синхронизации доступа к буферу
    private let bufferQueue = DispatchQueue(label: "com.particleflow.buffer", qos: .userInitiated)
    
    // Хранит исходные пиксели для сборки частиц (защищен bufferQueue)
    private var sourcePixels: [Pixel] = []
    
    // Хранит целевые частицы изображения (HQ targets)
    private var imageTargets: [Particle] = []

    // Хранит целевые частицы для разброса (scatter targets)
    private var scatterTargets: [Particle] = []
    
    // Прогресс перехода для сбора частиц (защищен bufferQueue)
    private var transitionProgress: Float = 0
    
    // MARK: - Constants
    private let boundsPadding: Float = 0.01                    // отступ от границ NDC [-1, 1]
    private let highQualityParticleSize: Float = 3.0           // размер частиц высокого качества
    private let scatteredParticleSize: Float = 1.0             // размер разбросанных частиц
    private let jitterRange: Float = 50.0                      // диапазон джиттера при создании частиц из пиксела
    private let previewRandomRangeNDC: Float = 0.9             // диапазон случайных позиций для preview в NDC
    
    // MARK: - Initialization
    init?(device: MTLDevice,
          logger: LoggerProtocol,
          viewSize: CGSize) {
        self.device = device
        self.logger = logger
        self.viewWidth = Float(viewSize.width)
        self.viewHeight = Float(viewSize.height)
        logger.info("ParticleStorage initialized")
    }
    
    
    // MARK: - Private Helper Methods
    private func copyParticlesToBuffer(_ particles: [Particle]) {
        guard let particleBuffer = particleBuffer else {
            logger.error("Particle buffer is nil")
            return
        }
        
        let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        
        for (index, particle) in particles.enumerated() {
            bufferPointer[index] = particle
        }
        
        // no-op: keep logs minimal
    }
    
    /// Создает частицу с позицией в NDC [-1, 1]
    /// Creates a particle positioned in Normalized Device Coordinates (NDC).
    ///
    /// The colour **must** be supplied – it is derived from the source image.
    /// If a colour is not provided the function will log an error and return a
    /// particle with a transparent colour (alpha = 0) to make the issue visible
    /// during debugging.
    private func createNDCParticle(
        x: Float,
        y: Float,
        color: SIMD4<Float>,
        size: Float = 1.0
    ) -> Particle {
        // Clamp position to stay inside the view bounds with a small padding.
        let clampedX = min(max(x, -1.0 + boundsPadding), 1.0 - boundsPadding)
        let clampedY = min(max(y, -1.0 + boundsPadding), 1.0 - boundsPadding)
        let pos = SIMD3<Float>(clampedX, clampedY, 0)
        let vel = SIMD3<Float>(
            Float.random(in: -0.1...0.1),
            Float.random(in: -0.1...0.1),
            0
        )
        
        // Гарантируем видимость частицы: альфа >= 0.6
        var safeColor = color
        if safeColor.w < 0.6 {
            safeColor.w = 0.8 // Устанавливаем минимальную видимую альфу
        }
        
        return Particle(
            position: pos,
            velocity: vel,
            targetPosition: pos,
            color: safeColor,
            originalColor: safeColor,
            size: size,
            baseSize: size,
            life: 0.0,
            idleChaoticMotion: 0
        )
    }
    /// Создает случайную частицу в заданных границах
    /// Returns a random colour taken from the current `sourcePixels` array.
    /// If the array is empty a neutral white colour is returned – this makes the
    /// situation visible during debugging.
    private func randomSourceColor() -> SIMD4<Float> {
        guard !sourcePixels.isEmpty else { return SIMD4<Float>(1, 1, 1, 1) }
        let randomPixel = sourcePixels.randomElement()!
        return pixelToColor(randomPixel)
    }
    
    private func createRandomParticle(in xRange: ClosedRange<Float>,
                                      _ yRange: ClosedRange<Float>) -> Particle {
        let x = Float.random(in: xRange)
        let y = Float.random(in: yRange)
        let clampedX = min(max(x, -1.0 + boundsPadding), 1.0 - boundsPadding)
        let clampedY = min(max(y, -1.0 + boundsPadding), 1.0 - boundsPadding)
        // Use a colour sampled from the source image to keep visual consistency.
        let colour = randomSourceColor()
        return createNDCParticle(x: clampedX, y: clampedY, color: colour)
    }
    
    /// Создает разбросанную частицу в случайных позициях в NDC [-1, 1]
    private func createScatteredParticle() -> Particle {
        // Генерируем случайные NDC координаты с разбросом
        let ndcX = Float.random(in: -1.0...1.0)
        let ndcY = Float.random(in: -1.0...1.0)
        // Ограничиваем границами с отступом
        let clampedX = min(max(ndcX, -1.0 + boundsPadding), 1.0 - boundsPadding)
        let clampedY = min(max(ndcY, -1.0 + boundsPadding), 1.0 - boundsPadding)
        // Assign a colour from the source image if possible.
        let colour = randomSourceColor()
        return createNDCParticle(x: clampedX, y: clampedY, color: colour)
    }
    
    /// Создает частицу из пикселя с нормализацией в NDC и джиттером
    private func createParticleFromPixel(_ px: Pixel, viewWidth: Float, viewHeight: Float) -> Particle {
        // Нормализуем координаты под NDC (-1..1) с учётом размеров экрана, с джиттером
        let jitterX = Float.random(in: -jitterRange...jitterRange)
        let jitterY = Float.random(in: -jitterRange...jitterRange)
        let pos = normalizePixelToNDC(px, viewWidth: viewWidth, viewHeight: viewHeight, jitterX: jitterX, jitterY: jitterY)
        let color = pixelToColor(px)
        return createNDCParticle(x: pos.x, y: pos.y, color: color)
    }
    /// Нормализует координаты пикселя в NDC [-1, 1] с учетом джиттера и отступа
    private func normalizePixelToNDC(
        _ px: Pixel,
        viewWidth: Float,
        viewHeight: Float,
        jitterX: Float = 0,
        jitterY: Float = 0
    ) -> SIMD3<Float> {
        let normalizedX = ((Float(px.x) + jitterX) / viewWidth) * 2.0 - 1.0
        // Pixel coordinates are top-left (UIKit), NDC is bottom-left (Metal).
        // Invert Y to map correctly into NDC space.
        let normalizedY = (1.0 - ((Float(px.y) + jitterY) / viewHeight)) * 2.0 - 1.0
        let clampedX = min(max(normalizedX, -1.0 + boundsPadding), 1.0 - boundsPadding)
        let clampedY = min(max(normalizedY, -1.0 + boundsPadding), 1.0 - boundsPadding)
        return SIMD3<Float>(clampedX, clampedY, 0)
    }
    
    /// Конвертирует Pixel в SIMD4<Float> цвет
    private func pixelToColor(_ px: Pixel) -> SIMD4<Float> {
        return SIMD4<Float>(
            Float(px.r)/255.0,
            Float(px.g)/255.0,
            Float(px.b)/255.0,
            Float(px.a)/255.0
        )
    }
    
    /// Вычисляет границы из sourcePixels
    private func calculateBoundsFromPixels() -> (ClosedRange<Float>, ClosedRange<Float>) {
        let xs = sourcePixels.map { Float($0.x) }
        let ys = sourcePixels.map { Float($0.y) }
        
        if let minX = xs.min(), let maxX = xs.max(),
           let minY = ys.min(), let maxY = ys.max() {
            return (minX...maxX, minY...maxY)
        } else {
            return (0.0...1.0, 0.0...1.0)
        }
    }
}


// MARK: - ParticleStorageProtocol Implementation
extension ParticleStorage: ParticleStorageProtocol {
    func initialize(with particleCount: Int) {
        logger.info("Initializing storage for \(particleCount) particles")
        
        self.particleCount = particleCount
        
        // Создаем буфер
        let bufferSize = MemoryLayout<Particle>.stride * particleCount
        particleBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        
        if let buffer = particleBuffer {
            memset(buffer.contents(), 0, bufferSize)
            // buffer created
        } else {
            logger.error("Failed to create particle buffer")
        }
    }
    
    func setSourcePixels(_ pixels: [Pixel]) {
        bufferQueue.sync {
            self.sourcePixels = pixels
        }
    }

    func updateViewSize(_ size: CGSize) {
        bufferQueue.sync {
            viewWidth = max(1, Float(size.width))
            viewHeight = max(1, Float(size.height))
        }
    }
    
    func createFastPreviewParticles() {
        guard particleCount > 0, particleBuffer != nil else {
            logger.warning("Cannot create preview particles - storage not initialized")
            return
        }

        let (currentViewWidth, currentViewHeight, currentSourcePixels) = bufferQueue.sync {
            (viewWidth, viewHeight, sourcePixels)
        }
        
        var particles: [Particle] = []
        particles.reserveCapacity(particleCount)
        
        if !currentSourcePixels.isEmpty {
            let count = min(particleCount, currentSourcePixels.count)
            
            // Создаем частицы из sourcePixels
            for i in 0..<count {
                particles.append(
                    createParticleFromPixel(
                        currentSourcePixels[i],
                        viewWidth: currentViewWidth,
                        viewHeight: currentViewHeight
                    )
                )
            }
            
            // Заполнение оставшихся частиц
            if particleCount > currentSourcePixels.count {
                let (xRange, yRange) = calculateBoundsFromPixels()
                for _ in count..<particleCount {
                    particles.append(createRandomParticle(in: xRange, yRange))
                }
            }
        } else {
            // Если sourcePixels нет, создаем случайные частицы в видимой области NDC
            for _ in 0..<particleCount {
                let x = Float.random(in: -previewRandomRangeNDC...previewRandomRangeNDC)
                let y = Float.random(in: -previewRandomRangeNDC...previewRandomRangeNDC)
                // Use a colour sampled from the source image if possible; otherwise fallback to white.
                let colour = randomSourceColor()
                particles.append(
                    createNDCParticle(
                        x: x,
                        y: y,
                        color: colour,
                        size: highQualityParticleSize
                    )
                )
            }
        }
        
        precondition(particles.count == particleCount)
        
        // Сохраняем частицы в буфер
        updateParticles(particles)
        
        logger.info("Fast preview particles created")
    }
    
    func recreateHighQualityParticles() {
        bufferQueue.sync {
            guard let particleBuffer = particleBuffer else {
                logger.warning("No particle buffer for high quality recreation")
                return
            }
            
            let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
            
            if !sourcePixels.isEmpty {
                // Устанавливаем targetPosition как HQ позиции из sourcePixels, нормализованные в NDC [-1,1]
                let count = min(particleCount, sourcePixels.count)
                for i in 0..<count {
                    let px = sourcePixels[i]
                    let targetPos = normalizePixelToNDC(px, viewWidth: viewWidth, viewHeight: viewHeight)
                    bufferPointer[i].targetPosition = targetPos
                    // Также обновляем цвет и размер для HQ
                    bufferPointer[i].color = SIMD4<Float>(
                        Float(px.r)/255.0,
                        Float(px.g)/255.0,
                        Float(px.b)/255.0,
                        Float(px.a)/255.0
                    )
                    bufferPointer[i].size = highQualityParticleSize
                    bufferPointer[i].baseSize = highQualityParticleSize
                }
                
                // Для оставшихся частиц устанавливаем случайные targetPosition
                for i in count..<particleCount {
                    bufferPointer[i].targetPosition = SIMD3<Float>(
                        Float.random(in: -1.0...1.0),
                        Float.random(in: -1.0...1.0),
                        0
                    )
                    // Assign a colour sampled from the source image if possible; otherwise fallback to white.
                    // Use explicit self to satisfy capture semantics inside the closure.
                    bufferPointer[i].color = self.randomSourceColor()
                    bufferPointer[i].originalColor = bufferPointer[i].color
                    bufferPointer[i].size = highQualityParticleSize
                    bufferPointer[i].baseSize = highQualityParticleSize
                }
            } else {
                // Fallback: устанавливаем targetPosition как текущую position
                for i in 0..<particleCount {
                    bufferPointer[i].targetPosition = bufferPointer[i].position
                }
            }
            
            // Сбрасываем прогресс для плавного перехода
            transitionProgress = 0
            logger.info("Recreated high quality particles")
        }
    }
    
    func createScatteredTargets() {
        bufferQueue.sync {
            scatterTargets = []
            scatterTargets.reserveCapacity(particleCount)
            
            if !sourcePixels.isEmpty {
                // Используем sourcePixels для создания разбросанных целей
                let count = min(particleCount, sourcePixels.count)
                // Разброс как доля от размеров экрана (20% от ширины/высоты)
                let scatterRangeX = viewWidth * 0.2
                let scatterRangeY = viewHeight * 0.2
                
                for i in 0..<count {
                    let px = sourcePixels[i]
                    
                    // Разбрасываем позиции вокруг оригинальных в экранных координатах
                    let scatterX = Float.random(in: -scatterRangeX...scatterRangeX)
                    let scatterY = Float.random(in: -scatterRangeY...scatterRangeY)
                    let scatteredScreenX = Float(px.x) + scatterX
                    let scatteredScreenY = Float(px.y) + scatterY
                    
                    // Нормализуем в NDC координаты
                    let normalizedX = (scatteredScreenX / viewWidth) * 2.0 - 1.0
                    let normalizedY = (scatteredScreenY / viewHeight) * 2.0 - 1.0
                    let clampedX = min(max(normalizedX, -1.0 + boundsPadding), 1.0 - boundsPadding)
                    let clampedY = min(max(normalizedY, -1.0 + boundsPadding), 1.0 - boundsPadding)
                    let scatteredPos = SIMD3<Float>(clampedX, clampedY, 0)
                    
                    let color = pixelToColor(px)
                    let particle = Particle(
                        position: scatteredPos,
                        velocity: SIMD3<Float>(0, 0, 0),
                        targetPosition: scatteredPos,
                        color: color,
                        originalColor: color,
                        size: scatteredParticleSize,
                        baseSize: scatteredParticleSize,
                        life: 0.0,
                        idleChaoticMotion: 0
                    )
                    scatterTargets.append(particle)
                }
                
                // Остальные частицы
                for _ in count..<particleCount {
                    scatterTargets.append(createScatteredParticle())
                }
            } else {
                // Fallback: случайные разбросанные позиции
                for _ in 0..<particleCount {
                    scatterTargets.append(createScatteredParticle())
                }
            }
            
            transitionProgress = 0
            logger.info("Created scattered targets for breaking apart")
        }
    }

    func setHighQualityTargets(_ particles: [Particle]) {
        bufferQueue.sync {
            imageTargets = []
            imageTargets.reserveCapacity(particleCount)

            if particles.count >= particleCount {
                imageTargets.append(contentsOf: particles.prefix(particleCount))
            } else {
                imageTargets.append(contentsOf: particles)
                let missing = particleCount - particles.count
                for _ in 0..<missing {
                    imageTargets.append(createScatteredParticle())
                }
            }

            transitionProgress = 0
            logger.info("High quality targets set: \(imageTargets.count)")
        }
    }

    func applyHighQualityTargetsToBuffer() {
        bufferQueue.sync {
            guard let particleBuffer = particleBuffer else {
                logger.warning("No particle buffer for applying HQ targets")
                return
            }

            let count = min(particleCount, imageTargets.count)
            guard count > 0 else {
                logger.warning("No high quality targets available to apply")
                return
            }

            let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)

            for i in 0..<count {
                let target = imageTargets[i]
                bufferPointer[i].targetPosition = target.targetPosition
                bufferPointer[i].color = target.color
                bufferPointer[i].originalColor = target.originalColor
                bufferPointer[i].size = target.size
                bufferPointer[i].baseSize = target.baseSize
                bufferPointer[i].life = 0.0
            }

            logger.info("Applied high quality targets to buffer: \(count)")
        }
    }

    func applyScatteredTargetsToBuffer() {
        bufferQueue.sync {
            guard let particleBuffer = particleBuffer else {
                logger.warning("No particle buffer for applying scattered targets")
                return
            }

            let count = min(particleCount, scatterTargets.count)
            guard count > 0 else {
                logger.warning("No scattered targets available to apply")
                return
            }

            let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)

            for i in 0..<count {
                let target = scatterTargets[i]
                bufferPointer[i].targetPosition = target.targetPosition
                bufferPointer[i].color = target.color
                bufferPointer[i].originalColor = target.originalColor
                bufferPointer[i].size = target.size
                bufferPointer[i].baseSize = target.baseSize
                bufferPointer[i].life = 0.0
            }

            logger.info("Applied scattered targets to buffer: \(count)")
        }
    }
    
    func updateFastPreview(deltaTime: Float) {
        bufferQueue.sync { /* гарантируем завершение всех CPU-записей */ }
        integrateVelocities(deltaTime: deltaTime)
    }
    
    func integrateVelocities(deltaTime: Float) {
        bufferQueue.sync {
            guard particleCount > 0, let particleBuffer = particleBuffer else {
                logger.warning("Cannot integrate velocities - invalid state")
                return
            }
            
            let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
            
            // NDC границы: [-1, 1] с отступом boundsPadding
            let minBound: Float = -1.0 + boundsPadding   // ≈ -0.99
            let maxBound: Float = 1.0 - boundsPadding    // ≈ 0.99
            
            for i in 0..<particleCount {
                var p = bufferPointer[i]
                
                // Обновляем позицию с учетом скорости
                p.position.x += p.velocity.x * deltaTime
                p.position.y += p.velocity.y * deltaTime
                
                // Ограничение по границам NDC
                p.position.x = max(minBound, min(p.position.x, maxBound))
                p.position.y = max(minBound, min(p.position.y, maxBound))
                
                // Коррекция скорости при столкновении с границей (отскок)
                if p.position.x <= minBound || p.position.x >= maxBound {
                    p.velocity.x *= -0.5
                }
                if p.position.y <= minBound || p.position.y >= maxBound {
                    p.velocity.y *= -0.5
                }
                
                // Защита от залипания: если скорость слишком мала, добавляем случайный толчок
                if simd.length(p.velocity) < 0.001 {
                    p.velocity = SIMD3<Float>(
                        Float.random(in: -0.01...0.01),
                        Float.random(in: -0.01...0.01),
                        0
                    )
                }
                
                bufferPointer[i] = p
            }
        }
    }
    
    func updateHighQualityTransition(deltaTime: Float) {
        bufferQueue.sync {
            let count = min(particleCount, imageTargets.count)
            guard count > 0, let particleBuffer = particleBuffer else {
                logger.warning("No high quality particles or buffer for transition")
                return
            }
            
            let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
            
            // Скорость интерполяции: 2.0 = 50% в секунду (полный переход за ~2 секунды)
            let lerpSpeed: Float = 2.0
            let lerpFactor = min(1.0, lerpSpeed * deltaTime)
            transitionProgress = min(1.0, transitionProgress + lerpFactor)
            
            for i in 0..<count {
                let target = imageTargets[i]
                var current = bufferPointer[i]
                
                // Интерполяция всех полей
                current.position += (target.position - current.position) * lerpFactor
                current.velocity += (target.velocity - current.velocity) * lerpFactor
                current.targetPosition += (target.targetPosition - current.targetPosition) * lerpFactor
                current.color += (target.color - current.color) * lerpFactor
                current.originalColor += (target.originalColor - current.originalColor) * lerpFactor
                current.size += (target.size - current.size) * lerpFactor
                current.baseSize += (target.baseSize - current.baseSize) * lerpFactor
                current.life += (target.life - current.life) * lerpFactor
                // idleChaoticMotion - uint, не интерполируется, берем из target
                if lerpFactor >= 0.9 {
                    current.idleChaoticMotion = target.idleChaoticMotion
                }
                
                bufferPointer[i] = current
            }
            
            // no-op: keep logs minimal
        }
    }
    
    func clear() {
        bufferQueue.sync {
            particleBuffer = nil
            particleCount = 0
            sourcePixels.removeAll()
            imageTargets.removeAll()
            scatterTargets.removeAll()
            transitionProgress = 0
            
            logger.info("Particle storage cleared")
        }
    }
    
    func getTransitionProgress() -> Float {
        bufferQueue.sync { transitionProgress }
    }
    
    func saveHighQualityPixels(from particles: [Particle]) {
        bufferQueue.sync {
            sourcePixels = particles.map { particle in
                // Преобразуем NDC координаты [-1, 1] в экранные координаты [0, viewWidth] x [0, viewHeight]
                let screenX = (particle.position.x + 1.0) * 0.5 * viewWidth
                let screenY = (particle.position.y + 1.0) * 0.5 * viewHeight
                
                return Pixel(
                    x: Int(screenX.rounded()),
                    y: Int(screenY.rounded()),
                    r: UInt8(clamping: Int((particle.color.x * 255).rounded())),
                    g: UInt8(clamping: Int((particle.color.y * 255).rounded())),
                    b: UInt8(clamping: Int((particle.color.z * 255).rounded())),
                    a: UInt8(clamping: Int((particle.color.w * 255).rounded()))
                )
            }
            logger.info("Saved high-quality pixels for collection")
        }
    }
    
    func updateParticles(_ particles: [Particle]) {
        bufferQueue.sync {
            copyParticlesToBuffer(particles)
        }
    }
    
    func updateParticles(_ particles: [Particle], startIndex: Int) {
        bufferQueue.sync {
            guard let particleBuffer = particleBuffer else {
                logger.error("Particle buffer is nil")
                return
            }
            guard startIndex >= 0, startIndex + particles.count <= particleCount else {
                logger.warning("Invalid startIndex or particles count for updateParticles")
                return
            }
            
            let bufferPointer = particleBuffer.contents()
                .bindMemory(to: Particle.self, capacity: particleCount)
            
            for (i, particle) in particles.enumerated() {
                bufferPointer[startIndex + i] = particle
            }
            
            // no-op: keep logs minimal
        }
    }
    
    func generateHighQualityParticles(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            var shouldSkip = false
            self.bufferQueue.sync {
                if !self.imageTargets.isEmpty {
                    shouldSkip = true
                    return
                }
                self.imageTargets = []
                self.imageTargets.reserveCapacity(self.particleCount)
                
                if !self.sourcePixels.isEmpty {
                    let count = min(self.particleCount, self.sourcePixels.count)
                    
                    for i in 0..<count {
                        let px = self.sourcePixels[i]
                        // Нормализуем координаты пикселя в NDC (с учётом инверсии Y)
                        let pos = self.normalizePixelToNDC(px, viewWidth: self.viewWidth, viewHeight: self.viewHeight)
                        let color = self.pixelToColor(px)
                        let particle = self.createNDCParticle(x: pos.x, y: pos.y, color: color, size: self.highQualityParticleSize)
                        self.imageTargets.append(particle)
                    }
                    
                    // Для оставшихся частиц случайные позиции в NDC [-1,1]
                    for _ in count..<self.particleCount {
                        let randX = Float.random(in: -1.0...1.0)
                        let randY = Float.random(in: -1.0...1.0)
                        let colour = self.randomSourceColor()
                        let particle = self.createNDCParticle(x: randX, y: randY, color: colour, size: self.highQualityParticleSize)
                        self.imageTargets.append(particle)
                    }
                } else {
                    // Если sourcePixels нет — случайные HQ частицы в NDC [-1,1]
                    for _ in 0..<self.particleCount {
                        let randX = Float.random(in: -1.0...1.0)
                        let randY = Float.random(in: -1.0...1.0)
                        let colour = self.randomSourceColor()
                        let particle = self.createNDCParticle(x: randX, y: randY, color: colour, size: self.highQualityParticleSize)
                        self.imageTargets.append(particle)
                    }
                }
                
                self.transitionProgress = 0
                self.logger.info("High quality particles generated")
            }

            if shouldSkip {
                self.logger.info("High quality targets already set - skipping generation")
                DispatchQueue.main.async {
                    completion()
                }
                return
            }
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
}
