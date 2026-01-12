//
//  ParticleGenerator.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import MetalKit
import Foundation

final class ParticleGenerator {
    
    weak var weakParticleSystem: ParticleSystem?
    
    // MARK: - Dependencies
    private weak var particleSystem: ParticleSystem?
    private let imageController: ImageParticleGeneratorProtocol
    private let particleCount: Int
    
    // MARK: - State
    private var screenSize: CGSize = .zero
    private static var loggedParticleBoundsKey: UInt8 = 0
    
    // MARK: - Computed Properties
    private var loggedParticleBounds: Bool {
        get {
            objc_getAssociatedObject(self, &ParticleGenerator.loggedParticleBoundsKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &ParticleGenerator.loggedParticleBoundsKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    // MARK: - Init
    init(particleSystem: ParticleSystem?,
         imageController: ImageParticleGeneratorProtocol,
         particleCount: Int) {
        self.particleSystem = particleSystem
        self.imageController = imageController
        self.particleCount = particleCount
    }
    
    // MARK: - Public API
    func updateScreenSize(_ size: CGSize) {
        screenSize = size
        imageController.updateScreenSize(size)
    }
    
    func recreateParticles(in buffer: MTLBuffer) {
        precondition(screenSize.width > 0 && screenSize.height > 0,
                    "screenSize must be set before creating particles")

        var particles: [Particle]
        do {
            particles = try imageController.generateParticles()
        } catch {
            Logger.shared.error("Failed to generate particles: \(error)")
            particles = createSimpleParticles()
        }
        
        let imgW = CGFloat(imageController.image.width)
        let imgH = CGFloat(imageController.image.height)
        
        if imgW > 0 && imgH > 0 && !(imageController is ImageParticleGenerator) {
            particles = applyImageScaling(particles, imgW: imgW, imgH: imgH)
        } else if imgW <= 0 || imgH <= 0 {
            particles = createSimpleParticles()
        }
        
        copyParticlesToBuffer(particles, buffer: buffer)
        logParticleBoundsOnce(particles)
    }

    /// Создает и копирует простые частицы в буфер (быстрый метод)
    func createAndCopySimpleParticles(in buffer: MTLBuffer) {
        let particles = createSimpleParticles()
        copyParticlesToBuffer(particles, buffer: buffer)
        logParticleBoundsOnce(particles)
    }
    
    // MARK: - Private Methods
    private func applyImageScaling(_ particles: [Particle], imgW: CGFloat, imgH: CGFloat) -> [Particle] {
        let scaleX = screenSize.width / imgW
        let scaleY = screenSize.height / imgH
        let scale = min(scaleX, scaleY)
        
        let scaledImgW = imgW * scale
        let scaledImgH = imgH * scale
        let offsetX = (screenSize.width - scaledImgW) / 2.0
        let offsetY = (screenSize.height - scaledImgH) / 2.0
        
        var scaledParticles = particles
        
        for i in 0..<scaledParticles.count {
            // Scale and offset target position
            scaledParticles[i].targetPosition.x =
                Float(scaledParticles[i].targetPosition.x * Float(scale) + Float(offsetX))
            scaledParticles[i].targetPosition.y =
                Float(scaledParticles[i].targetPosition.y * Float(scale) + Float(offsetY))
            
            // Randomize initial position
            scaledParticles[i].position = SIMD3<Float>(
                Float.random(in: 0..<Float(screenSize.width)),
                Float.random(in: 0..<Float(screenSize.height)),
                0
            )
        }
        
        return scaledParticles
    }
    
    private func createSimpleParticles() -> [Particle] {
        guard particleCount > 0 else { return [] }
        
        var particles: [Particle] = []
        particles.reserveCapacity(particleCount)
        
        let scrSize: CGSize
        if let view = particleSystem?.mtkViewForGenerator, view.drawableSize.width > 0 {
            scrSize = view.drawableSize
        } else if screenSize.width > 0 {
            scrSize = screenSize
        } else {
            scrSize = CGSize(width: 1024, height: 768)
        }
        
        let particlesPerRow = Int(sqrt(Double(particleCount)))
        let particlesPerColumn = (particleCount + particlesPerRow - 1) / particlesPerRow
        
        let stepX = scrSize.width / CGFloat(particlesPerRow)
        let stepY = scrSize.height / CGFloat(particlesPerColumn)
        
        for row in 0..<particlesPerColumn {
            for col in 0..<particlesPerRow {
                let index = row * particlesPerRow + col
                guard index < particleCount else { break }
                
                var p = Particle()
                
                let baseX = stepX * CGFloat(col) + stepX / 2
                let baseY = stepY * CGFloat(row) + stepY / 2
                
                p.position = SIMD3<Float>(Float(baseX), Float(baseY), 0)
                p.targetPosition = p.position
                p.size = 4
                p.baseSize = 4
                p.color = SIMD4<Float>(1, 1, 1, 1)
                p.originalColor = p.color
                p.life = 0
                p.idleChaoticMotion = 0
                
                particles.append(p)
            }
        }
        
        return particles
    }
    
    private func copyParticlesToBuffer(_ particles: [Particle], buffer: MTLBuffer) {
        let ptr = buffer
            .contents()
            .assumingMemoryBound(to: Particle.self)
        
        for i in 0..<particleCount {
            ptr[i] = i < particles.count ? particles[i] : Particle()
        }
    }
    
    private func logParticleBoundsOnce(_ particles: [Particle]) {
        guard !loggedParticleBounds else { return }
        loggedParticleBounds = true
        
        let xs = particles.map { $0.position.x }
        let ys = particles.map { $0.position.y }
        
        Logger.shared.debug("Particles: \(particles.count)")
        Logger.shared.debug("X: \(xs.min() ?? 0)...\(xs.max() ?? 0)")
        Logger.shared.debug("Y: \(ys.min() ?? 0)...\(ys.max() ?? 0)")
    }
}
