//
//  ParticleAssembler.swift
//  PixelFlow
//
//  Компонент для сборки частиц из сэмплов пикселей
//  - Преобразование сэмплов в структуры Particle
//  - Масштабирование под экран
//  - Настройка цветов и размеров
//

import Foundation
import simd
import CoreGraphics

// MARK: - API Errors

enum ParticleAssemblerError: Error, LocalizedError {
    case emptySamples
    case invalidImageSize(CGSize)
    case invalidScreenSize(CGSize)
    case invalidOriginalImageSize(CGSize)
    
    var errorDescription: String? {
        switch self {
        case .emptySamples:
            return "Samples array is empty."
        case .invalidImageSize(let size):
            return "Invalid image size: \(size)."
        case .invalidScreenSize(let size):
            return "Invalid screen size: \(size)."
        case .invalidOriginalImageSize(let size):
            return "Invalid original image size: \(size)."
        }
    }
}

// MARK: - Default Particle Assembler

final class DefaultParticleAssembler: ParticleAssembler, ParticleAssemblerProtocol {
    
    // MARK: - Constants
    
    private enum VelocityConstants {
        // КРИТИЧНО: Скорость должна быть в NDC пространстве [-1, 1], а не в пиксельях!
        // NDC диапазон: 2.0 (от -1 до 1), тогда как пиксельное пространство может быть 1000+
        // Поэтому используем намного меньшие значения для NDC
        static let maxSpeedNDC: Float = 0.5
        static let baseAmount: Float = 0.1
        static let chaosFactor: Float = 0.5
        static let chaosRandomRange: UInt32 = 200
        static let randomRange: UInt32 = 500
    }
    
    private enum QualityMultipliers {
        static let ultra: Float = 1.0      // Ultra: наименьший размер (максимум частиц)
        static let high: Float = 1.2       // High: средний размер
        static let standard: Float = 1.5   // Standard: больший размер
        static let draft: Float = 2.0      // Draft: максимальный размер (минимум частиц)
    }
    
    private enum SizeRanges {
        static let ultra: ClosedRange<Float> = 0.8...15.0
        static let high: ClosedRange<Float> = 1.5...12.0
        static let standard: ClosedRange<Float> = 2.0...9.0
        static let draft: ClosedRange<Float> = 3.0...7.0
    }
    
    private enum ParticleDefaults {
        static let minPixelSize: Float = 1.0
        static let initialLife: Float = 0.0
        static let idleChaoticMotion: Int = 0
    }
    
    // MARK: - Properties
    
    private let config: ParticleGenerationConfig
    
    // MARK: - Initialization
    
    init(config: ParticleGenerationConfig) {
        self.config = config
    }
    
    // MARK: - Public API
    
    func assembleParticles(
        from samples: [Sample],
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        imageSize: CGSize,
        originalImageSize: CGSize
    ) -> [Particle] {
        do {
            return try assembleParticlesInternal(
                from: samples,
                config: config,
                screenSize: screenSize,
                imageSize: imageSize,
                originalImageSize: originalImageSize
            )
        } catch {
            Logger.shared.error("Particle assembly failed: \(error)")
            return []
        }
    }
    
    // MARK: - Internal Assembly
    
    private func assembleParticlesInternal(
        from samples: [Sample],
        config: ParticleGenerationConfig,
        screenSize: CGSize,
        imageSize: CGSize,
        originalImageSize: CGSize
    ) throws -> [Particle] {
        
        try validateInputs(
            samples: samples,
            imageSize: imageSize,
            screenSize: screenSize
        )
        
        let displayMode = config.imageDisplayMode
        let isFullRes = isFullResolution(config: config, imageSize: imageSize)
        
        let transformation = calculateTransformation(
            screenSize: screenSize,
            imageSize: imageSize,
            displayMode: displayMode,
            snapToIntScale: isFullRes
        )
        
        logTransformationInfo(
            displayMode: displayMode,
            screenSize: screenSize,
            imageSize: imageSize,
            originalImageSize: originalImageSize,
            transformation: transformation
        )
        
        let assemblyContext = createAssemblyContext(
            config: config,
            transformation: transformation,
            imageSize: imageSize,
            originalImageSize: originalImageSize,
            screenSize: screenSize
        )
        
        let particles = generateParticles(
            from: samples,
            context: assemblyContext
        )
        
        #if DEBUG
        logAssemblyResults(particles, screenSize: screenSize)
        #endif
        
        return particles
    }
    
    // MARK: - Validation
    
    private func validateInputs(
        samples: [Sample],
        imageSize: CGSize,
        screenSize: CGSize
    ) throws {
        guard !samples.isEmpty else {
            throw ParticleAssemblerError.emptySamples
        }
        
        guard imageSize.width > 0, imageSize.height > 0 else {
            throw ParticleAssemblerError.invalidImageSize(imageSize)
        }
        
        guard screenSize.width > 0, screenSize.height > 0 else {
            throw ParticleAssemblerError.invalidScreenSize(screenSize)
        }
    }
    
    private func isFullResolution(config: ParticleGenerationConfig, imageSize: CGSize) -> Bool {
        return config.targetParticleCount >= Int(imageSize.width * imageSize.height)
    }
    
    // MARK: - Transformation Calculation
    
    @inline(__always)
    private func calculateTransformation(
        screenSize: CGSize,
        imageSize: CGSize,
        displayMode: ImageDisplayMode,
        snapToIntScale: Bool
    ) -> TransformationParams {
        
        switch displayMode {
        case .fit:
            return calculateFitTransformation(
                screenSize: screenSize,
                imageSize: imageSize,
                snapToIntScale: snapToIntScale
            )
            
        case .fill:
            return calculateFillTransformation(
                screenSize: screenSize,
                imageSize: imageSize,
                snapToIntScale: snapToIntScale
            )
            
        case .stretch:
            return calculateStretchTransformation(
                screenSize: screenSize,
                imageSize: imageSize,
                snapToIntScale: snapToIntScale
            )
            
        case .center:
            return calculateCenterTransformation(
                screenSize: screenSize,
                imageSize: imageSize,
                snapToIntScale: snapToIntScale
            )
        }
    }
    
    private func calculateFitTransformation(
        screenSize: CGSize,
        imageSize: CGSize,
        snapToIntScale: Bool
    ) -> TransformationParams {
        
        var scale = min(
            screenSize.width / imageSize.width,
            screenSize.height / imageSize.height
        )
        
        if snapToIntScale && scale >= 1.0 {
            scale = floor(scale)
        }
        
        let offset = calculateCenteredOffset(
            screenSize: screenSize,
            imageSize: imageSize,
            scale: scale,
            snapToIntScale: snapToIntScale
        )
        
        let centerOffset = snapToIntScale ? CGPoint(x: 0.5, y: 0.5) : .zero
        
        return TransformationParams(
            scaleX: scale,
            scaleY: scale,
            offset: offset,
            pixelCenterOffset: centerOffset,
            mode: .fit
        )
    }
    
    private func calculateFillTransformation(
        screenSize: CGSize,
        imageSize: CGSize,
        snapToIntScale: Bool
    ) -> TransformationParams {
        
        let aspectImage = imageSize.width / imageSize.height
        let aspectScreen = screenSize.width / screenSize.height
        
        var scale = (aspectImage > aspectScreen)
            ? screenSize.height / imageSize.height
            : screenSize.width / imageSize.width
        
        if snapToIntScale && scale >= 1.0 {
            scale = ceil(scale)
        }
        
        let offset = calculateCenteredOffset(
            screenSize: screenSize,
            imageSize: imageSize,
            scale: scale,
            snapToIntScale: snapToIntScale
        )
        
        let centerOffset = snapToIntScale ? CGPoint(x: 0.5, y: 0.5) : .zero
        
        return TransformationParams(
            scaleX: scale,
            scaleY: scale,
            offset: offset,
            pixelCenterOffset: centerOffset,
            mode: .fill
        )
    }
    
    private func calculateStretchTransformation(
        screenSize: CGSize,
        imageSize: CGSize,
        snapToIntScale: Bool
    ) -> TransformationParams {
        
        let scaleX = screenSize.width / imageSize.width
        let scaleY = screenSize.height / imageSize.height
        let centerOffset = snapToIntScale ? CGPoint(x: 0.5, y: 0.5) : .zero
        
        return TransformationParams(
            scaleX: scaleX,
            scaleY: scaleY,
            offset: .zero,
            pixelCenterOffset: centerOffset,
            mode: .stretch
        )
    }
    
    private func calculateCenterTransformation(
        screenSize: CGSize,
        imageSize: CGSize,
        snapToIntScale: Bool
    ) -> TransformationParams {
        
        let offset = CGPoint(
            x: (screenSize.width - imageSize.width) / 2,
            y: (screenSize.height - imageSize.height) / 2
        )
        
        let centerOffset = snapToIntScale ? CGPoint(x: 0.5, y: 0.5) : .zero
        
        return TransformationParams(
            scaleX: 1.0,
            scaleY: 1.0,
            offset: offset,
            pixelCenterOffset: centerOffset,
            mode: .center
        )
    }
    
    private func calculateCenteredOffset(
        screenSize: CGSize,
        imageSize: CGSize,
        scale: CGFloat,
        snapToIntScale: Bool
    ) -> CGPoint {
        
        let scaledWidth = imageSize.width * scale
        let scaledHeight = imageSize.height * scale
        
        let rawOffset = CGPoint(
            x: (screenSize.width - scaledWidth) / 2,
            y: (screenSize.height - scaledHeight) / 2
        )
        
        return snapToIntScale
            ? CGPoint(x: rawOffset.x.rounded(), y: rawOffset.y.rounded())
            : rawOffset
    }
    
    // MARK: - Assembly Context
    
    private struct AssemblyContext {
        let transformation: TransformationParams
        let sizeRange: ClosedRange<Float>
        let qualityMultiplier: Float
        let imageSize: CGSize
        let originalImageSize: CGSize
        let screenSize: CGSize
    }
    
    private func createAssemblyContext(
        config: ParticleGenerationConfig,
        transformation: TransformationParams,
        imageSize: CGSize,
        originalImageSize: CGSize,
        screenSize: CGSize
    ) -> AssemblyContext {
        
        let sizeRange = getSizeRange(for: config.qualityPreset)
        let qualityMultiplier = getQualityMultiplier(for: config.qualityPreset)
        
        return AssemblyContext(
            transformation: transformation,
            sizeRange: sizeRange,
            qualityMultiplier: qualityMultiplier,
            imageSize: imageSize,
            originalImageSize: originalImageSize,
            screenSize: screenSize
        )
    }
    
    private func getSizeRange(for preset: QualityPreset) -> ClosedRange<Float> {
        switch preset {
        case .ultra:
            return config.particleSizeUltra ?? SizeRanges.ultra
        case .high:
            return config.particleSizeHigh ?? SizeRanges.high
        case .standard:
            return config.particleSizeStandard ?? SizeRanges.standard
        case .draft:
            return config.particleSizeLow ?? SizeRanges.draft
        }
    }
    
    private func getQualityMultiplier(for preset: QualityPreset) -> Float {
        switch preset {
        case .ultra:
            return QualityMultipliers.ultra
        case .high:
            return QualityMultipliers.high
        case .standard:
            return QualityMultipliers.standard
        case .draft:
            return QualityMultipliers.draft
        @unknown default:
            return QualityMultipliers.ultra
        }
    }
    
    // MARK: - Particle Generation
    
    private func generateParticles(
        from samples: [Sample],
        context: AssemblyContext
    ) -> [Particle] {
        
        var particles: [Particle] = []
        particles.reserveCapacity(samples.count)
        
        for (index, sample) in samples.enumerated() {
            let particle = createParticle(
                from: sample,
                index: index,
                context: context
            )
            particles.append(particle)
        }
        
        return particles
    }
    
    @inline(__always)
    private func createParticle(
        from sample: Sample,
        index: Int,
        context: AssemblyContext
    ) -> Particle {
        
        guard context.originalImageSize.width > 0, context.originalImageSize.height > 0 else {
            return Particle()
        }
        
        var particle = Particle()
        
        let normalizedCoords = calculateNormalizedCoordinates(
            sample: sample,
            originalImageSize: context.originalImageSize
        )
        
        let screenCoords = transformToScreenCoordinates(
            normalized: normalizedCoords,
            context: context
        )
        
        let ndcPosition = convertToNDC(
            screenCoords: screenCoords,
            screenSize: context.screenSize
        )
        
        particle.position = SIMD3<Float>(ndcPosition.x, ndcPosition.y, 0)
        particle.targetPosition = particle.position
        
        particle.color = sample.color
        particle.originalColor = sample.color
        
        particle.size = calculateParticleSize(
            transformation: context.transformation,
            qualityMultiplier: context.qualityMultiplier
        )
        particle.baseSize = particle.size
        
        particle.life = ParticleDefaults.initialLife
        particle.idleChaoticMotion = UInt32(ParticleDefaults.idleChaoticMotion)
        
        particle.velocity = calculateVelocity(
            sample: sample,
            index: index
        )
        
        return particle
    }
    
    // MARK: - Coordinate Transformations
    
    private func calculateNormalizedCoordinates(
        sample: Sample,
        originalImageSize: CGSize
    ) -> (x: CGFloat, y: CGFloat) {
        
        let nx = (CGFloat(sample.x) + 0.5) / originalImageSize.width
        let ny = (CGFloat(sample.y) + 0.5) / originalImageSize.height
        
        return (nx, ny)
    }
    
    private func transformToScreenCoordinates(
        normalized: (x: CGFloat, y: CGFloat),
        context: AssemblyContext
    ) -> (x: CGFloat, y: CGFloat) {
        
        let displayedWidth = context.imageSize.width * context.transformation.scaleX
        let displayedHeight = context.imageSize.height * context.transformation.scaleY
        
        let screenX = context.transformation.offset.x +
                      normalized.x * displayedWidth +
                      context.transformation.pixelCenterOffset.x
        
        let screenY = context.transformation.offset.y +
                      normalized.y * displayedHeight +
                      context.transformation.pixelCenterOffset.y
        
        return (screenX, screenY)
    }
    
    private func convertToNDC(
        screenCoords: (x: CGFloat, y: CGFloat),
        screenSize: CGSize
    ) -> (x: Float, y: Float) {
        
        // normalized → NDC [-1…1]
        // Инверсия Y: UIKit (Y вниз) → Metal (Y вверх)
        let ndcX = Float(screenCoords.x / screenSize.width * 2.0 - 1.0)
        let ndcY = Float((1.0 - screenCoords.y / screenSize.height) * 2.0 - 1.0)
        
        return (ndcX, ndcY)
    }
    
    // MARK: - Size Calculation
    
    private func calculateParticleSize(
        transformation: TransformationParams,
        qualityMultiplier: Float
    ) -> Float {
        
        let pixelWidth = Float(transformation.scaleX)
        let pixelHeight = Float(transformation.scaleY)
        var pixelSize = min(pixelWidth, pixelHeight)
        
        // В pixel-perfect режиме используем целочисленный размер >= 1px
        pixelSize = max(ParticleDefaults.minPixelSize, ceil(pixelSize))
        
        return pixelSize * qualityMultiplier
    }
    
    // MARK: - Velocity Calculation
    
    private func calculateVelocity(
        sample: Sample,
        index: Int
    ) -> SIMD3<Float> {
        
        var seed = createSeed(sample: sample, index: index)
        
        let chaosFactor = VelocityConstants.chaosFactor +
                         Float(xorshift32(&seed) % VelocityConstants.chaosRandomRange) / 1000.0
        
        let vx = -VelocityConstants.baseAmount +
                Float(xorshift32(&seed) % VelocityConstants.randomRange) / 1000.0
        
        let vy = -VelocityConstants.baseAmount +
                Float(xorshift32(&seed) % VelocityConstants.randomRange) / 1000.0
        
        let velocity = SIMD3<Float>(vx, vy, 0) * VelocityConstants.maxSpeedNDC * chaosFactor
        
        return velocity
    }
    
    private func createSeed(sample: Sample, index: Int) -> UInt32 {
        return UInt32(sample.x) &* 73856093 ^
               UInt32(sample.y) &* 19349663 ^
               UInt32(index)
    }
    
    @inline(__always)
    private func xorshift32(_ value: inout UInt32) -> UInt32 {
        var x = value
        x ^= x << 13
        x ^= x >> 17
        x ^= x << 5
        value = x
        return x
    }
    
    // MARK: - Logging
    
    private func logTransformationInfo(
        displayMode: ImageDisplayMode,
        screenSize: CGSize,
        imageSize: CGSize,
        originalImageSize: CGSize,
        transformation: TransformationParams
    ) {
        Logger.shared.debug(
            "Assembler: mode=\(displayMode), " +
            "screen=\(screenSize.width)x\(screenSize.height), " +
            "image=\(imageSize.width)x\(imageSize.height), " +
            "original=\(originalImageSize.width)x\(originalImageSize.height), " +
            "scale=(\(transformation.scaleX),\(transformation.scaleY)), " +
            "offset=(\(transformation.offset.x),\(transformation.offset.y)), " +
            "centerOffset=(\(transformation.pixelCenterOffset.x),\(transformation.pixelCenterOffset.y))"
        )
    }
    
    #if DEBUG
    private func logAssemblyResults(_ particles: [Particle], screenSize: CGSize) {
        Logger.shared.debug("Сборка частиц завершена: \(particles.count) частиц")
        
        guard !particles.isEmpty else { return }
        
        logParticleBounds(particles, screenSize: screenSize)
        logParticleDetails(particles)
    }
    
    private func logParticleBounds(_ particles: [Particle], screenSize: CGSize) {
        var bounds = ParticleBounds()
        var uniquePixelY = Set<Int>()
        var outOfRangeY = 0
        
        for particle in particles {
            bounds.update(with: particle)
            
            let pixelY = Int(round((1.0 - particle.position.y) * 0.5 * Float(screenSize.height)))
            bounds.updatePixelY(pixelY)
            
            if pixelY < 0 || pixelY >= Int(screenSize.height) {
                outOfRangeY += 1
            } else {
                uniquePixelY.insert(pixelY)
            }
        }
        
        bounds.log(screenHeight: Int(screenSize.height), uniquePixelYCount: uniquePixelY.count, outOfRangeY: outOfRangeY)
        
        if uniquePixelY.count > 1 {
            let maxGap = calculateMaxGap(in: uniquePixelY)
            Logger.shared.debug("maxGap=\(maxGap)")
        }
    }
    
    private func calculateMaxGap(in pixelSet: Set<Int>) -> Int {
        let sorted = pixelSet.sorted()
        var maxGap = 0
        
        for i in 1..<sorted.count {
            let gap = sorted[i] - sorted[i - 1]
            if gap > maxGap {
                maxGap = gap
            }
        }
        
        return maxGap
    }
    
    private func logParticleDetails(_ particles: [Particle]) {
        guard particles.count >= 10 else { return }
        
        Logger.shared.debug("Первые 10 частиц (КОНТРОЛЬ ЦВЕТОВ):")
        
        for i in 0..<10 {
            let p = particles[i]
            logSingleParticle(p, index: i)
        }
    }
    
    private func logSingleParticle(_ particle: Particle, index: Int) {
        let color = formatColor(particle.color)
        let originalColor = formatColor(particle.originalColor)
        let position = formatPosition(particle.position)
        let velocity = formatVelocity(particle.velocity)
        
        Logger.shared.debug("  [\(index)] color=\(color) originalColor=\(originalColor)")
        Logger.shared.debug("       pos=\(position) vel=\(velocity)")
    }
    
    private func formatColor(_ color: SIMD4<Float>) -> String {
        let r = String(format: "%.3f", color.x)
        let g = String(format: "%.3f", color.y)
        let b = String(format: "%.3f", color.z)
        let a = String(format: "%.3f", color.w)
        return "(\(r),\(g),\(b),\(a))"
    }
    
    private func formatPosition(_ position: SIMD3<Float>) -> String {
        let x = String(format: "%.2f", position.x)
        let y = String(format: "%.2f", position.y)
        return "(\(x), \(y))"
    }
    
    private func formatVelocity(_ velocity: SIMD3<Float>) -> String {
        let x = String(format: "%.3f", velocity.x)
        let y = String(format: "%.3f", velocity.y)
        return "(\(x), \(y))"
    }
    
    // MARK: - Particle Bounds Helper
    
    private struct ParticleBounds {
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var minNdcY: Float = .greatestFiniteMagnitude
        var maxNdcY: Float = -.greatestFiniteMagnitude
        var minPixelY: Int = .max
        var maxPixelY: Int = .min
        
        mutating func update(with particle: Particle) {
            minX = min(minX, particle.position.x)
            maxX = max(maxX, particle.position.x)
            minY = min(minY, particle.position.y)
            maxY = max(maxY, particle.position.y)
            minNdcY = min(minNdcY, particle.position.y)
            maxNdcY = max(maxNdcY, particle.position.y)
        }
        
        mutating func updatePixelY(_ pixelY: Int) {
            minPixelY = min(minPixelY, pixelY)
            maxPixelY = max(maxPixelY, pixelY)
        }
        
        func log(screenHeight: Int, uniquePixelYCount: Int, outOfRangeY: Int) {
            Logger.shared.debug("Assembler bounds (NDC): x=[\(format(minX)), \(format(maxX))] y=[\(format(minY)), \(format(maxY))]")
            Logger.shared.debug("Assembler ndcY: min=\(format(minNdcY, precision: 5)) max=\(format(maxNdcY, precision: 5)), screenH=\(max(1, screenHeight)), pxY=[\(minPixelY)..\(maxPixelY)] uniquePxY=\(uniquePixelYCount), outOfRangeY=\(outOfRangeY)")
        }
        
        private func format(_ value: Float, precision: Int = 3) -> String {
            return String(format: "%.\(precision)f", value)
        }
    }
    #endif
}
