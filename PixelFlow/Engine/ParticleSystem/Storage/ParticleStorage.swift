//
//  ParticleStorage.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Хранилище частиц и управление буферами
//

import Metal

/// Хранилище частиц
final class ParticleStorage: ParticleStorageProtocol {

    // MARK: - Properties

    var particleBuffer: MTLBuffer?
    private(set) var particleCount: Int = 0

    private let device: MTLDevice
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(device: MTLDevice = MTLCreateSystemDefaultDevice()!,
         logger: LoggerProtocol = Logger.shared) {
        self.device = device
        self.logger = logger
        logger.info("ParticleStorage initialized")
    }

    // MARK: - ParticleStorageProtocol

    func createFastPreviewParticles() {
        logger.debug("Creating fast preview particles")

        guard particleCount > 0, particleBuffer != nil else {
            logger.warning("Cannot create preview particles - storage not initialized")
            return
        }

        // Создаем быстрые превью частицы (упрощенные)
        let particles = createPreviewParticles(count: particleCount)

        // Копируем в буфер
        copyParticlesToBuffer(particles)

        logger.info("Fast preview particles created: \(particles.count)")
    }

    func recreateHighQualityParticles() {
        logger.debug("Recreating high-quality particles")

        guard particleCount > 0, particleBuffer != nil else {
            logger.warning("Cannot create high-quality particles - storage not initialized")
            return
        }

        // Здесь будет получение высококачественных частиц от генератора
        // Пока создаем заглушки
        let particles = createHighQualityParticles(count: particleCount)

        // Копируем в буфер
        copyParticlesToBuffer(particles)

        logger.info("High-quality particles created: \(particles.count)")
    }

    func clear() {
        logger.debug("Clearing particle storage")

        // Очищаем буфер (в Metal буферы автоматически управляются)
        particleBuffer = nil
        particleCount = 0

        logger.info("Particle storage cleared")
    }

    // MARK: - Public Methods

    func initialize(with particleCount: Int) {
        logger.info("Initializing storage for \(particleCount) particles")

        self.particleCount = particleCount

        // Создаем буфер
        let bufferSize = MemoryLayout<Particle>.stride * particleCount
        particleBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)

        if particleBuffer == nil {
            logger.error("Failed to create particle buffer")
        } else {
            logger.info("Particle buffer created: \(bufferSize) bytes")
        }
    }

    func updateParticles(_ particles: [Particle]) {
        guard particles.count == particleCount, particleBuffer != nil else {
            logger.warning("Cannot update particles - invalid state")
            return
        }

        copyParticlesToBuffer(particles)
    }

    // MARK: - Private Methods

    private func createPreviewParticles(count: Int) -> [Particle] {
        var particles = [Particle]()

        for i in 0..<count {
            var particle = Particle()

            // Создаем простое превью распределение
            let angle = Float(i) / Float(count) * 2 * .pi
            let radius: Float = 100.0 + Float.random(in: 0...200)

            particle.position = SIMD3<Float>(
                cos(angle) * radius,
                sin(angle) * radius,
                0
            )

            particle.velocity = SIMD3<Float>(
                cos(angle + .pi/2) * 50,
                sin(angle + .pi/2) * 50,
                0
            )

            particle.color = SIMD4<Float>(
                Float.random(in: 0.5...1.0), // R
                Float.random(in: 0.5...1.0), // G
                Float.random(in: 0.5...1.0), // B
                1.0 // A
            )

            particle.size = Float.random(in: 2.0...8.0)

            particles.append(particle)
        }

        return particles
    }

    private func createHighQualityParticles(count: Int) -> [Particle] {
        // Заглушка для высококачественных частиц
        // В реальности здесь будут частицы от генератора изображений
        var particles = [Particle]()

        for i in 0..<count {
            var particle = Particle()

            // Создаем более сложное распределение для "высокого качества"
            let angle = Float(i) / Float(count) * 2 * .pi
            let radius: Float = 50.0 + Float(i % 10) * 20.0

            particle.position = SIMD3<Float>(
                cos(angle) * radius,
                sin(angle) * radius,
                0
            )

            particle.velocity = SIMD3<Float>(
                cos(angle + .pi/4) * 30,
                sin(angle + .pi/4) * 30,
                0
            )

            // Более насыщенные цвета для "высокого качества"
            particle.color = SIMD4<Float>(
                Float.random(in: 0.7...1.0),
                Float.random(in: 0.7...1.0),
                Float.random(in: 0.7...1.0),
                1.0
            )

            particle.size = Float.random(in: 3.0...12.0)

            particles.append(particle)
        }

        return particles
    }

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