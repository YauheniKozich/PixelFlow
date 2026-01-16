//
//  ParticleStorage.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Хранилище частиц и управление буферами
//

import Metal

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
final class ParticleStorage: ParticleStorageProtocol {
   
    
    // MARK: - Properties

    var particleBuffer: MTLBuffer?
    public private(set) var particleCount: Int = 0

    private let device: MTLDevice
    private let logger: LoggerProtocol

    // Хранит исходные пиксели для сборки частиц
    private var sourcePixels: [Pixel] = []
    
    // Хранит целевые высококачественные частицы для плавного перехода
    private var highQualityParticles: [Particle] = []

    // MARK: - Initialization

    init?(device: MTLDevice,
          logger: LoggerProtocol) {
        self.device = device
        self.logger = logger
        logger.info("ParticleStorage initialized")
    }

    // MARK: - ParticleStorageProtocol

    public func recreateHighQualityParticles() {
        guard let particleBuffer = particleBuffer else {
            logger.warning("Cannot recreate high quality particles - buffer is nil")
            return
        }
        
        let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        highQualityParticles = []
        highQualityParticles.reserveCapacity(particleCount)
        
        for i in 0..<particleCount {
            highQualityParticles.append(bufferPointer[i])
        }
        
        // Мгновенная замена частиц на высококачественные
        for i in 0..<particleCount {
            bufferPointer[i] = highQualityParticles[i]
        }
        
        logger.info("Recreated high quality particles: \(particleCount)")
    }

    func createFastPreviewParticles() {
        logger.debug("Creating fast preview particles with initial velocities")

        guard particleCount > 0, particleBuffer != nil else {
            logger.warning("Cannot create preview particles - storage not initialized")
            return
        }

        var particles: [Particle] = []
        particles.reserveCapacity(particleCount)

        if !sourcePixels.isEmpty {
            let count = min(particleCount, sourcePixels.count)
            for i in 0..<count {
                let px = sourcePixels[i]
                
                // Слегка разбросать позиции вокруг исходных пикселей
                let jitterX = Float.random(in: -50.0...50.0)  // Больше разброс
                let jitterY = Float.random(in: -50.0...50.0)
                let pos = SIMD3<Float>(Float(px.x) + jitterX, Float(px.y) + jitterY, 0)
                
                // Генерируем начальную скорость
                let vx = Float.random(in: -0.1...0.1)
                let vy = Float.random(in: -0.1...0.1)
                let vel = SIMD3<Float>(vx, vy, 0)
                
                let color = SIMD4<Float>(
                    Float(px.r)/255.0,
                    Float(px.g)/255.0,
                    Float(px.b)/255.0,
                    Float(px.a)/255.0
                )
                
                let particle = Particle(
                    position: pos,
                    velocity: vel,
                    targetPosition: pos,
                    color: color,
                    originalColor: color,
                    size: 1.0,
                    baseSize: 1.0,
                    life: 0.0,
                    idleChaoticMotion: 0
                )
                particles.append(particle)
            }
            
            // Заполнение оставшихся частиц
            if particleCount > sourcePixels.count {
                let remaining = particleCount - sourcePixels.count
                let xRange: ClosedRange<Float>
                let yRange: ClosedRange<Float>
                let xs = sourcePixels.map { Float($0.x) }
                let ys = sourcePixels.map { Float($0.y) }
                if let minX = xs.min(), let maxX = xs.max(), let minY = ys.min(), let maxY = ys.max() {
                    xRange = minX...maxX
                    yRange = minY...maxY
                } else {
                    xRange = 0.0...1.0
                    yRange = 0.0...1.0
                }
                
                for _ in 0..<remaining {
                    let x = Float.random(in: xRange)
                    let y = Float.random(in: yRange)
                    let pos = SIMD3<Float>(x, y, 0)
                    
                    let vx = Float.random(in: -0.1...0.1)
                    let vy = Float.random(in: -0.1...0.1)
                    let vel = SIMD3<Float>(vx, vy, 0)
                    
                    let particle = Particle(
                        position: pos,
                        velocity: vel,
                        targetPosition: pos,
                        color: SIMD4<Float>(1, 1, 1, 1),
                        originalColor: SIMD4<Float>(1, 1, 1, 1),
                        size: 1.0,
                        baseSize: 1.0,
                        life: 0.0,
                        idleChaoticMotion: 0
                    )
                    particles.append(particle)
                }
            }
        } else {
            // Если sourcePixels нет, создаем случайные частицы
            for _ in 0..<particleCount {
                let x = Float.random(in: 0.0...1.0)
                let y = Float.random(in: 0.0...1.0)
                let pos = SIMD3<Float>(x, y, 0)
                
                let vx = Float.random(in: -0.1...0.1)
                let vy = Float.random(in: -0.1...0.1)
                let vel = SIMD3<Float>(vx, vy, 0)
                
                let particle = Particle(
                    position: pos,
                    velocity: vel,
                    targetPosition: pos,
                    color: SIMD4<Float>(1, 1, 1, 1),
                    originalColor: SIMD4<Float>(1, 1, 1, 1),
                    size: 1.0,
                    baseSize: 1.0,
                    life: 0.0,
                    idleChaoticMotion: 0
                )
                particles.append(particle)
            }
        }

        precondition(particles.count == particleCount)

        // Сохраняем частицы в буфер
        updateParticles(particles)

        logger.info("Fast preview particles created: \(particles.count)")
    }
    
    /// Обновляет позиции fast preview частиц с учетом deltaTime
    func updateFastPreview(deltaTime: Float) {
        logger.debug("Updating fast preview particles with deltaTime \(deltaTime)")
        integrateVelocities(deltaTime: deltaTime)
    }

    func integrateVelocities(deltaTime: Float) {
        guard particleCount > 0, let particleBuffer = particleBuffer else {
            logger.warning("Cannot integrate velocities - invalid state")
            return
        }

        let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)

        for i in 0..<particleCount {
            var particle = bufferPointer[i]
            // Velocity уже хранится в структуре Particle
            particle.position += particle.velocity * deltaTime
            bufferPointer[i] = particle
        }

        logger.debug("Integrated velocities for \(particleCount) particles with deltaTime \(deltaTime)")
    }

    /// Плавное обновление позиций частиц для перехода к высококачественной сборке
    func updateHighQualityTransition(deltaTime: Float) {
        logger.debug("Updating high quality transition with deltaTime \(deltaTime)")

        let count = min(particleCount, highQualityParticles.count)
        guard count > 0, let particleBuffer = particleBuffer else {
            logger.warning("No high quality particles or buffer for transition")
            return
        }
        
        let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        
        // Скорость интерполяции: 2.0 = 50% в секунду (полный переход за ~2 секунды)
        let lerpSpeed: Float = 2.0
        let lerpFactor = min(1.0, lerpSpeed * deltaTime)
        
        for i in 0..<count {
            let target = highQualityParticles[i]
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
        
        logger.debug("High quality transition updated for \(count) particles")
    }

    func clear() {
        logger.debug("Clearing particle storage")

        particleBuffer = nil
        particleCount = 0
        sourcePixels.removeAll()
        highQualityParticles.removeAll()

        logger.info("Particle storage cleared")
    }

    // MARK: - Public Methods

    func initialize(with particleCount: Int) {
        logger.info("Initializing storage for \(particleCount) particles")

        self.particleCount = particleCount

        // Создаем буфер
        let bufferSize = MemoryLayout<Particle>.stride * particleCount
        particleBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)

        if let buffer = particleBuffer {
            memset(buffer.contents(), 0, bufferSize)
            logger.info("Particle buffer created and zero-initialized: \(bufferSize) bytes")
        } else {
            logger.error("Failed to create particle buffer")
        }
    }

    /// Устанавливает исходные пиксели для сборки частиц
    func setSourcePixels(_ pixels: [Pixel]) {
        logger.debug("Setting \(pixels.count) source pixels")
        self.sourcePixels = pixels
    }

    /// Полное обновление GPU буфера частиц
    func updateParticles(_ particles: [Particle]) {
        guard particles.count == particleCount, particleBuffer != nil else {
            logger.warning("Cannot update particles - invalid state")
            return
        }

        copyParticlesToBuffer(particles)
    }

    /// Инкрементальное обновление части GPU буфера частиц, начиная с startIndex
    func updateParticles(_ particles: [Particle], startIndex: Int) {
        guard let particleBuffer = particleBuffer else {
            logger.error("Particle buffer is nil")
            return
        }
        guard startIndex >= 0, startIndex + particles.count <= particleCount else {
            logger.warning("Invalid startIndex or particles count for updateParticles")
            return
        }
        let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)
        for (i, particle) in particles.enumerated() {
            bufferPointer[startIndex + i] = particle
        }
        logger.debug("Updated \(particles.count) particles in buffer at startIndex \(startIndex)")
    }

    // MARK: - Private Methods

    private func copyParticlesToBuffer(_ particles: [Particle]) {
        guard let particleBuffer = particleBuffer else {
            logger.error("Particle buffer is nil")
            return
        }

        let bufferPointer = particleBuffer.contents().bindMemory(to: Particle.self, capacity: particleCount)

        for (index, particle) in particles.enumerated() {
            bufferPointer[index] = particle
        }

        logger.debug("Particles copied to buffer: \(particles.count)")
    }
}
