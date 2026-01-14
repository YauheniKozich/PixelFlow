//
//  ParticleGenerator.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

//  ParticleGenerator.swift

import MetalKit
import Foundation
import UIKit
import simd

final class ParticleGenerator {
    
    // MARK: - Свойства
    
    weak var weakParticleSystem: ParticleSystem?
    
    private weak var particleSystem: ParticleSystem?
    private let imageController: ImageParticleGeneratorProtocol
    private let particleCount: Int
    
    private var screenSize: CGSize = .zero
    private static var loggedParticleBoundsKey: UInt8 = 0
    private var cachedImage: UIImage?
    
    private var loggedParticleBounds: Bool {
        get {
            objc_getAssociatedObject(self,
                                     &ParticleGenerator.loggedParticleBoundsKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self,
                                     &ParticleGenerator.loggedParticleBoundsKey,
                                     newValue,
                                     .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }
    
    // MARK: - Инициализация
    
    init(particleSystem: ParticleSystem?,
         imageController: ImageParticleGeneratorProtocol,
         particleCount: Int) {
        self.particleSystem = particleSystem
        self.imageController = imageController
        self.particleCount = particleCount
        self.cachedImage = UIImage(cgImage: imageController.image)
    }
    
    // MARK: - Публичные методы
    
    func updateScreenSize(_ size: CGSize) {
        screenSize = size
        imageController.updateScreenSize(size)
    }
    
    /// Основная генерация частиц (качественная)
    func recreateParticles(in buffer: MTLBuffer) {
        precondition(screenSize.width > 0 && screenSize.height > 0,
                     "screenSize must be set before creating particles")
        
        var particles: [Particle]
        
        do {
            particles = try imageController.generateParticles()
        } catch {
            particles = createFastLowQualityParticles()
        }
        
        let imgW = CGFloat(imageController.image.width)
        let imgH = CGFloat(imageController.image.height)
        
        if imgW > 0 && imgH > 0 && !(imageController is ImageParticleGenerator) {
            particles = applyImageScaling(particles,
                                          imgW: imgW,
                                          imgH: imgH)
        } else if imgW <= 0 || imgH <= 0 {
            particles = createFastLowQualityParticles()
        }
        
        copyParticlesToBuffer(particles, buffer: buffer)
        logParticleBoundsOnce(particles)
    }
    
    /// Быстрая генерация низкокачественных частиц
    func createAndCopyFastPreviewParticles(in buffer: MTLBuffer) {
        let particles = createFastLowQualityParticles()
        copyParticlesToBuffer(particles, buffer: buffer)
        logParticleBoundsOnce(particles)
    }
    
    // MARK: - Приватные методы
    
    private func applyImageScaling(_ particles: [Particle],
                                   imgW: CGFloat,
                                   imgH: CGFloat) -> [Particle] {
        
        let scaleX = screenSize.width / imgW
        let scaleY = screenSize.height / imgH
        let scale = min(scaleX, scaleY)
        
        let scaledImgW = imgW * scale
        let scaledImgH = imgH * scale
        let offsetX = (screenSize.width - scaledImgW) / 2.0
        let offsetY = (screenSize.height - scaledImgH) / 2.0
        
        var scaled = particles
        
        for i in 0..<scaled.count {
            scaled[i].targetPosition.x =
            Float(scaled[i].targetPosition.x * Float(scale) + Float(offsetX))
            scaled[i].targetPosition.y =
            Float(scaled[i].targetPosition.y * Float(scale) + Float(offsetY))
            
            scaled[i].position = SIMD3<Float>(
                Float.random(in: 0..<Float(screenSize.width)),
                Float.random(in: 0..<Float(screenSize.height)),
                0
            )
        }
        return scaled
    }
    
    private func createFastLowQualityParticles() -> [Particle] {
        guard particleCount > 0 else { return [] }
        
        var particles: [Particle] = []
        particles.reserveCapacity(particleCount)
        
        let scrSize: CGSize
        if let view = particleSystem?.mtkViewForGenerator,
           view.drawableSize.width > 0 {
            scrSize = view.drawableSize
        } else if screenSize.width > 0 {
            scrSize = screenSize
        } else {
            scrSize = CGSize(width: 1024, height: 768)
        }
        
        guard let image = getSourceCGImage() else {
            return createColorfulGradientParticles(count: particleCount,
                                                   screenSize: scrSize)
        }
        
        particles = createImprovedImageSamplingParticles(
            image: image,
            targetCount: particleCount,
            screenSize: scrSize
        )
        
        return particles
    }
    
    private func createImprovedImageSamplingParticles(image: CGImage,
                                                      targetCount: Int,
                                                      screenSize: CGSize) -> [Particle] {
        
        var particles: [Particle] = []
        particles.reserveCapacity(targetCount)
        
        let imgW = image.width
        let imgH = image.height
        
        let scaleX = Float(screenSize.width) / Float(imgW)
        let scaleY = Float(screenSize.height) / Float(imgH)
        let scale = min(scaleX, scaleY)
        
        let scaledImgW = Float(imgW) * scale
        let scaledImgH = Float(imgH) * scale
        let offsetX = (Float(screenSize.width) - scaledImgW) / 2.0
        let offsetY = (Float(screenSize.height) - scaledImgH) / 2.0
        
        guard let context = createImageContext(image: image) else {
            return createColorfulGradientParticles(count: targetCount,
                                                   screenSize: screenSize)
        }
        
        let bytesPerRow = context.bytesPerRow
        let data = context.data!.assumingMemoryBound(to: UInt8.self)
        
        let totalPixels = imgW * imgH
        let sampleRate = max(1,
                             Int(round(Double(totalPixels) / Double(targetCount))))
        
        var collected = 0
        
        for y in 0..<imgH {
            for x in 0..<imgW {
                if ((y * imgW + x) % sampleRate) != 0 { continue }
                if collected >= targetCount { break }
                
                let color = getPixelColorSafe(
                    from: data,
                    x: x,
                    y: y,
                    width: imgW,
                    height: imgH,
                    bytesPerRow: bytesPerRow
                )
                
                var particle = Particle()
                
                let nx = Float(x) / Float(imgW)
                let ny = Float(y) / Float(imgH)
                
                let screenX = offsetX + nx * scaledImgW
                let screenY = offsetY + ny * scaledImgH
                
                particle.position = SIMD3<Float>(screenX, screenY, 0)
                particle.targetPosition = particle.position
                particle.size = 4
                particle.baseSize = 4
                particle.color = color
                particle.originalColor = color
                particle.life = 0
                particle.idleChaoticMotion = 0
                
                particles.append(particle)
                collected += 1
            }
            if collected >= targetCount { break }
        }
        
        while particles.count < targetCount && collected < targetCount {
            let x = Int.random(in: 0..<imgW)
            let y = Int.random(in: 0..<imgH)
            
            let color = getPixelColorSafe(
                from: data,
                x: x,
                y: y,
                width: imgW,
                height: imgH,
                bytesPerRow: bytesPerRow
            )
            
            var particle = Particle()
            
            let nx = Float(x) / Float(imgW)
            let ny = Float(y) / Float(imgH)
            
            let screenX = offsetX + nx * scaledImgW
            let screenY = offsetY + ny * scaledImgH
            
            particle.position = SIMD3<Float>(screenX, screenY, 0)
            particle.targetPosition = particle.position
            particle.size = 4
            particle.baseSize = 4
            particle.color = color
            particle.originalColor = color
            particle.life = 0
            particle.idleChaoticMotion = 0
            
            particles.append(particle)
            collected += 1
        }
        
        return particles
    }
    
    private func getSourceCGImage() -> CGImage? {
        return imageController.image
    }
    
    private func createImageContext(image: CGImage) -> CGContext? {
        let width = image.width
        let height = image.height
        
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let bitmapInfo = CGImageAlphaInfo.premultipliedLast.rawValue |
        CGBitmapInfo.byteOrder32Big.rawValue
        
        guard let ctx = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: bitmapInfo
        ) else { return nil }
        
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        return ctx
    }
    
    private func getPixelColorSafe(from data: UnsafeMutablePointer<UInt8>,
                                   x: Int,
                                   y: Int,
                                   width: Int,
                                   height: Int,
                                   bytesPerRow: Int) -> SIMD4<Float> {
        
        guard x >= 0 && x < width && y >= 0 && y < height else {
            return SIMD4<Float>(0.5, 0.5, 0.5, 1.0)
        }
        
        let index = y * bytesPerRow + x * 4
        
        let r = Float(data[index]) / 255.0
        let g = Float(data[index + 1]) / 255.0
        let b = Float(data[index + 2]) / 255.0
        let a = Float(data[index + 3]) / 255.0
        
        return SIMD4<Float>(r, g, b, a)
    }
    
    private func createColorfulGradientParticles(count: Int,
                                                 screenSize: CGSize) -> [Particle] {
        var particles: [Particle] = []
        particles.reserveCapacity(count)
        
        let grid = Int(sqrt(Double(count)))
        
        for i in 0..<count {
            var particle = Particle()
            
            let x = Float(i % grid) * Float(screenSize.width) / Float(grid)
            let y = Float(i / grid) * Float(screenSize.height) / Float(grid)
            
            particle.position = SIMD3<Float>(x, y, 0)
            particle.targetPosition = particle.position
            particle.size = 4
            particle.baseSize = 4
            
            let normX = x / Float(screenSize.width)
            let normY = y / Float(screenSize.height)
            
            let r, g, b: Float
            if normY < 0.5 {
                if normX < 0.5 {
                    r = 0.15 + Float.random(in: -0.05...0.05)
                    g = 0.10 + Float.random(in: -0.05...0.05)
                    b = 0.05 + Float.random(in: -0.05...0.05)
                } else {
                    r = 0.7 + Float.random(in: -0.1...0.1)
                    g = 0.5 + Float.random(in: -0.1...0.1)
                    b = 0.3 + Float.random(in: -0.1...0.1)
                }
            } else {
                r = 0.9 + Float.random(in: -0.1...0.1)
                g = 0.9 + Float.random(in: -0.1...0.1)
                b = 0.9 + Float.random(in: -0.1...0.1)
            }
            
            particle.color = SIMD4<Float>(max(0, min(1, r)),
                                          max(0, min(1, g)),
                                          max(0, min(1, b)),
                                          1.0)
            particle.originalColor = particle.color
            particle.life = 0
            particle.idleChaoticMotion = 0
            
            particles.append(particle)
        }
        
        return particles
    }
    
    private func copyParticlesToBuffer(_ particles: [Particle],
                                       buffer: MTLBuffer) {
        let ptr = buffer.contents()
            .assumingMemoryBound(to: Particle.self)
        
        for i in 0..<particleCount {
            ptr[i] = i < particles.count ? particles[i] : Particle()
        }
    }
    
    private func logParticleBoundsOnce(_ particles: [Particle]) {
        guard !loggedParticleBounds else { return }
        loggedParticleBounds = true
    }
    
    // MARK: - Очистка
    
    func cleanup() {
        loggedParticleBounds = false
        weakParticleSystem = nil
        particleSystem = nil
        screenSize = .zero
        cachedImage = nil
    }
}
