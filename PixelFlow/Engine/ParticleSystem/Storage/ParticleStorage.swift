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

// MARK: - Particle Storage

/// Хранилище частиц
final class ParticleStorage {
    
    // MARK: - Constants
    
    private enum Constants {
        static let boundsPadding: Float = 0.01
        static let highQualityParticleSize: Float = 3.0
        static let scatteredParticleSize: Float = 1.0
        static let jitterRange: Float = 50.0
        static let previewRandomRangeNDC: Float = 0.9
        static let minVisibleAlpha: Float = 0.6
        static let safeAlpha: Float = 0.8
        static let scatterRatio: Float = 0.2
        static let lerpSpeed: Float = 2.0
        static let velocityReboundFactor: Float = -0.5
        static let minVelocityThreshold: Float = 0.001
        static let randomVelocityRange: Float = 0.1
        static let randomImpulseRange: Float = 0.01
        static let lerpThreshold: Float = 0.9
    }
    
    private enum NDCBounds {
        static let min: Float = -1.0
        static let max: Float = 1.0
        
        static var minWithPadding: Float {
            min + Constants.boundsPadding
        }
        
        static var maxWithPadding: Float {
            max - Constants.boundsPadding
        }
    }
    
    // MARK: - Properties
    
    var particleBuffer: MTLBuffer?
    public private(set) var particleCount: Int = 0
    
    private let device: MTLDevice
    private let logger: LoggerProtocol
    
    private var viewWidth: Float
    private var viewHeight: Float
    
    private let bufferQueue = DispatchQueue(
        label: "com.particleflow.buffer",
        qos: .userInitiated
    )
    
    private var sourcePixels: [Pixel] = []
    private var imageTargets: [Particle] = []
    private var scatterTargets: [Particle] = []
    private var transitionProgress: Float = 0
    
    // MARK: - Initialization
    
    init?(
        device: MTLDevice,
        logger: LoggerProtocol,
        viewSize: CGSize
    ) {
        self.device = device
        self.logger = logger
        self.viewWidth = Float(viewSize.width)
        self.viewHeight = Float(viewSize.height)
        logger.info("ParticleStorage initialized")
    }
    
    // MARK: - Buffer Management
    
    private func copyParticlesToBuffer(_ particles: [Particle]) {
        guard let particleBuffer = particleBuffer else {
            logger.error("Particle buffer is nil")
            return
        }
        
        let bufferPointer = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: particleCount
        )
        
        for (index, particle) in particles.enumerated() {
            bufferPointer[index] = particle
        }
    }
    
    // MARK: - Particle Creation
    
    private func createNDCParticle(
        x: Float,
        y: Float,
        color: SIMD4<Float>,
        size: Float = 1.0
    ) -> Particle {
        
        let position = clampToNDCBounds(x: x, y: y)
        let velocity = generateRandomVelocity()
        let safeColor = ensureVisibleColor(color)
        
        return Particle(
            position: position,
            velocity: velocity,
            targetPosition: position,
            color: safeColor,
            originalColor: safeColor,
            size: size,
            baseSize: size,
            life: 0.0,
            idleChaoticMotion: 0
        )
    }
    
    private func clampToNDCBounds(x: Float, y: Float) -> SIMD3<Float> {
        let clampedX = clamp(x, min: NDCBounds.minWithPadding, max: NDCBounds.maxWithPadding)
        let clampedY = clamp(y, min: NDCBounds.minWithPadding, max: NDCBounds.maxWithPadding)
        return SIMD3<Float>(clampedX, clampedY, 0)
    }
    
    private func generateRandomVelocity() -> SIMD3<Float> {
        return SIMD3<Float>(
            Float.random(in: -Constants.randomVelocityRange...Constants.randomVelocityRange),
            Float.random(in: -Constants.randomVelocityRange...Constants.randomVelocityRange),
            0
        )
    }
    
    private func ensureVisibleColor(_ color: SIMD4<Float>) -> SIMD4<Float> {
        var safeColor = color
        if safeColor.w < Constants.minVisibleAlpha {
            safeColor.w = Constants.safeAlpha
        }
        return safeColor
    }
    
    private func createParticleFromPixel(
        _ px: Pixel,
        viewWidth: Float,
        viewHeight: Float
    ) -> Particle {
        
        let jitter = generateJitter()
        let position = normalizePixelToNDC(
            px,
            viewWidth: viewWidth,
            viewHeight: viewHeight,
            jitterX: jitter.x,
            jitterY: jitter.y
        )
        let color = pixelToColor(px)
        
        return createNDCParticle(x: position.x, y: position.y, color: color)
    }
    
    private func generateJitter() -> (x: Float, y: Float) {
        return (
            Float.random(in: -Constants.jitterRange...Constants.jitterRange),
            Float.random(in: -Constants.jitterRange...Constants.jitterRange)
        )
    }
    
    private func createRandomParticle(
        in xRange: ClosedRange<Float>,
        _ yRange: ClosedRange<Float>
    ) -> Particle {
        
        let x = Float.random(in: xRange)
        let y = Float.random(in: yRange)
        let color = randomSourceColor()
        
        return createNDCParticle(x: x, y: y, color: color)
    }
    
    private func createScatteredParticle() -> Particle {
        let ndcX = Float.random(in: NDCBounds.min...NDCBounds.max)
        let ndcY = Float.random(in: NDCBounds.min...NDCBounds.max)
        let color = randomSourceColor()
        
        return createNDCParticle(x: ndcX, y: ndcY, color: color)
    }
    
    // MARK: - Color Management
    
    private func randomSourceColor() -> SIMD4<Float> {
        guard !sourcePixels.isEmpty else {
            return SIMD4<Float>(1, 1, 1, 1)
        }
        
        let randomPixel = sourcePixels.randomElement()!
        return pixelToColor(randomPixel)
    }
    
    private func pixelToColor(_ px: Pixel) -> SIMD4<Float> {
        return SIMD4<Float>(
            Float(px.r) / 255.0,
            Float(px.g) / 255.0,
            Float(px.b) / 255.0,
            Float(px.a) / 255.0
        )
    }
    
    // MARK: - Coordinate Transformation
    
    private func normalizePixelToNDC(
        _ px: Pixel,
        viewWidth: Float,
        viewHeight: Float,
        jitterX: Float = 0,
        jitterY: Float = 0
    ) -> SIMD3<Float> {
        
        let normalizedX = ((Float(px.x) + jitterX) / viewWidth) * 2.0 - 1.0
        // Pixel coordinates are top-left (UIKit), NDC is bottom-left (Metal)
        let normalizedY = (1.0 - ((Float(px.y) + jitterY) / viewHeight)) * 2.0 - 1.0
        
        return clampToNDCBounds(x: normalizedX, y: normalizedY)
    }
    
    private func calculateBoundsFromPixels() -> (ClosedRange<Float>, ClosedRange<Float>) {
        guard !sourcePixels.isEmpty else {
            return (0.0...1.0, 0.0...1.0)
        }
        
        let xs = sourcePixels.map { Float($0.x) }
        let ys = sourcePixels.map { Float($0.y) }
        
        guard let minX = xs.min(), let maxX = xs.max(),
              let minY = ys.min(), let maxY = ys.max() else {
            return (0.0...1.0, 0.0...1.0)
        }
        
        return (minX...maxX, minY...maxY)
    }
    
    // MARK: - Utility
    
    private func clamp<T: Comparable>(_ value: T, min minValue: T, max maxValue: T) -> T {
        return Swift.min(Swift.max(value, minValue), maxValue)
    }
}

// MARK: - ParticleStorageProtocol Implementation

extension ParticleStorage: ParticleStorageProtocol {
    
    // MARK: - Initialization
    
    func initialize(with particleCount: Int) {
        logger.info("Initializing storage for \(particleCount) particles")
        
        self.particleCount = particleCount
        
        let bufferSize = MemoryLayout<Particle>.stride * particleCount
        particleBuffer = device.makeBuffer(length: bufferSize, options: .storageModeShared)
        
        if let buffer = particleBuffer {
            memset(buffer.contents(), 0, bufferSize)
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
    
    // MARK: - Fast Preview
    
    func createFastPreviewParticles() {
        guard particleCount > 0, particleBuffer != nil else {
            logger.warning("Cannot create preview particles - storage not initialized")
            return
        }
        
        let context = bufferQueue.sync {
            PreviewContext(
                viewWidth: viewWidth,
                viewHeight: viewHeight,
                sourcePixels: sourcePixels
            )
        }
        
        let particles = generatePreviewParticles(context: context)
        updateParticles(particles)
        
        logger.info("Fast preview particles created")
    }
    
    private struct PreviewContext {
        let viewWidth: Float
        let viewHeight: Float
        let sourcePixels: [Pixel]
    }
    
    private func generatePreviewParticles(context: PreviewContext) -> [Particle] {
        var particles: [Particle] = []
        particles.reserveCapacity(particleCount)
        
        if !context.sourcePixels.isEmpty {
            particles = generateParticlesFromSource(context: context)
        } else {
            particles = generateRandomPreviewParticles()
        }
        
        precondition(particles.count == particleCount)
        return particles
    }
    
    private func generateParticlesFromSource(context: PreviewContext) -> [Particle] {
        var particles: [Particle] = []
        let count = min(particleCount, context.sourcePixels.count)
        
        // Создаем частицы из sourcePixels
        for i in 0..<count {
            let particle = createParticleFromPixel(
                context.sourcePixels[i],
                viewWidth: context.viewWidth,
                viewHeight: context.viewHeight
            )
            particles.append(particle)
        }
        
        // Заполнение оставшихся частиц
        if particleCount > context.sourcePixels.count {
            let (xRange, yRange) = calculateBoundsFromPixels()
            for _ in count..<particleCount {
                particles.append(createRandomParticle(in: xRange, yRange))
            }
        }
        
        return particles
    }
    
    private func generateRandomPreviewParticles() -> [Particle] {
        var particles: [Particle] = []
        
        for _ in 0..<particleCount {
            let x = Float.random(in: -Constants.previewRandomRangeNDC...Constants.previewRandomRangeNDC)
            let y = Float.random(in: -Constants.previewRandomRangeNDC...Constants.previewRandomRangeNDC)
            let color = randomSourceColor()
            
            particles.append(
                createNDCParticle(
                    x: x,
                    y: y,
                    color: color,
                    size: Constants.highQualityParticleSize
                )
            )
        }
        
        return particles
    }
    
    // MARK: - High Quality Recreation
    
    func recreateHighQualityParticles() {
        bufferQueue.sync {
            guard let particleBuffer = particleBuffer else {
                logger.warning("No particle buffer for high quality recreation")
                return
            }
            
            let bufferPointer = particleBuffer.contents().bindMemory(
                to: Particle.self,
                capacity: particleCount
            )
            
            if !sourcePixels.isEmpty {
                updateBufferWithSourcePixels(bufferPointer: bufferPointer)
            } else {
                fallbackToCurrentPositions(bufferPointer: bufferPointer)
            }
            
            transitionProgress = 0
            logger.info("Recreated high quality particles")
        }
    }
    
    private func updateBufferWithSourcePixels(bufferPointer: UnsafeMutablePointer<Particle>) {
        let count = min(particleCount, sourcePixels.count)
        
        for i in 0..<count {
            let px = sourcePixels[i]
            let targetPos = normalizePixelToNDC(px, viewWidth: viewWidth, viewHeight: viewHeight)
            
            bufferPointer[i].targetPosition = targetPos
            bufferPointer[i].color = pixelToColor(px)
            bufferPointer[i].size = Constants.highQualityParticleSize
            bufferPointer[i].baseSize = Constants.highQualityParticleSize
        }
        
        fillRemainingWithRandom(bufferPointer: bufferPointer, startIndex: count)
    }
    
    private func fillRemainingWithRandom(
        bufferPointer: UnsafeMutablePointer<Particle>,
        startIndex: Int
    ) {
        for i in startIndex..<particleCount {
            bufferPointer[i].targetPosition = SIMD3<Float>(
                Float.random(in: NDCBounds.min...NDCBounds.max),
                Float.random(in: NDCBounds.min...NDCBounds.max),
                0
            )
            bufferPointer[i].color = randomSourceColor()
            bufferPointer[i].originalColor = bufferPointer[i].color
            bufferPointer[i].size = Constants.highQualityParticleSize
            bufferPointer[i].baseSize = Constants.highQualityParticleSize
        }
    }
    
    private func fallbackToCurrentPositions(bufferPointer: UnsafeMutablePointer<Particle>) {
        for i in 0..<particleCount {
            bufferPointer[i].targetPosition = bufferPointer[i].position
        }
    }
    
    // MARK: - Scattered Targets
    
    func createScatteredTargets() {
        bufferQueue.sync {
            scatterTargets = generateScatteredTargets()
            transitionProgress = 0
            logger.info("Created scattered targets for breaking apart")
        }
    }
    
    private func generateScatteredTargets() -> [Particle] {
        var targets: [Particle] = []
        targets.reserveCapacity(particleCount)
        
        if !sourcePixels.isEmpty {
            targets = generateScatteredFromSource()
        } else {
            targets = generateRandomScattered()
        }
        
        return targets
    }
    
    private func generateScatteredFromSource() -> [Particle] {
        var targets: [Particle] = []
        let count = min(particleCount, sourcePixels.count)
        
        let scatterRange = ScatterRange(
            x: viewWidth * Constants.scatterRatio,
            y: viewHeight * Constants.scatterRatio
        )
        
        for i in 0..<count {
            let particle = createScatteredFromPixel(sourcePixels[i], scatterRange: scatterRange)
            targets.append(particle)
        }
        
        for _ in count..<particleCount {
            targets.append(createScatteredParticle())
        }
        
        return targets
    }
    
    private struct ScatterRange {
        let x: Float
        let y: Float
    }
    
    private func createScatteredFromPixel(_ px: Pixel, scatterRange: ScatterRange) -> Particle {
        let scatter = (
            x: Float.random(in: -scatterRange.x...scatterRange.x),
            y: Float.random(in: -scatterRange.y...scatterRange.y)
        )
        
        let scatteredScreen = (
            x: Float(px.x) + scatter.x,
            y: Float(px.y) + scatter.y
        )
        
        let normalized = (
            x: (scatteredScreen.x / viewWidth) * 2.0 - 1.0,
            y: (scatteredScreen.y / viewHeight) * 2.0 - 1.0
        )
        
        let scatteredPos = clampToNDCBounds(x: normalized.x, y: normalized.y)
        let color = pixelToColor(px)
        
        return Particle(
            position: scatteredPos,
            velocity: SIMD3<Float>(0, 0, 0),
            targetPosition: scatteredPos,
            color: color,
            originalColor: color,
            size: Constants.scatteredParticleSize,
            baseSize: Constants.scatteredParticleSize,
            life: 0.0,
            idleChaoticMotion: 0
        )
    }
    
    private func generateRandomScattered() -> [Particle] {
        return (0..<particleCount).map { _ in createScatteredParticle() }
    }
    
    // MARK: - Target Management
    
    func setHighQualityTargets(_ particles: [Particle]) {
        bufferQueue.sync {
            imageTargets = prepareHighQualityTargets(from: particles)
            transitionProgress = 0
            logger.info("High quality targets set: \(imageTargets.count)")
        }
    }
    
    private func prepareHighQualityTargets(from particles: [Particle]) -> [Particle] {
        var targets: [Particle] = []
        targets.reserveCapacity(particleCount)
        
        if particles.count >= particleCount {
            targets.append(contentsOf: particles.prefix(particleCount))
        } else {
            targets.append(contentsOf: particles)
            let missing = particleCount - particles.count
            for _ in 0..<missing {
                targets.append(createScatteredParticle())
            }
        }
        
        return targets
    }
    
    func applyHighQualityTargetsToBuffer() {
        bufferQueue.sync {
            applyTargetsToBuffer(targets: imageTargets, name: "HQ")
        }
    }
    
    func applyScatteredTargetsToBuffer() {
        bufferQueue.sync {
            applyTargetsToBuffer(targets: scatterTargets, name: "scattered")
        }
    }
    
    private func applyTargetsToBuffer(targets: [Particle], name: String) {
        guard let particleBuffer = particleBuffer else {
            logger.warning("No particle buffer for applying \(name) targets")
            return
        }
        
        let count = min(particleCount, targets.count)
        guard count > 0 else {
            logger.warning("No \(name) targets available to apply")
            return
        }
        
        let bufferPointer = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: particleCount
        )
        
        for i in 0..<count {
            applyTargetToParticle(target: targets[i], bufferPointer: bufferPointer, index: i)
        }
        
        logger.info("Applied \(name) targets to buffer: \(count)")
    }
    
    private func applyTargetToParticle(
        target: Particle,
        bufferPointer: UnsafeMutablePointer<Particle>,
        index: Int
    ) {
        bufferPointer[index].targetPosition = target.targetPosition
        bufferPointer[index].color = target.color
        bufferPointer[index].originalColor = target.originalColor
        bufferPointer[index].size = target.size
        bufferPointer[index].baseSize = target.baseSize
        bufferPointer[index].life = 0.0
    }
    
    // MARK: - Update Methods
    
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
            
            let bufferPointer = particleBuffer.contents().bindMemory(
                to: Particle.self,
                capacity: particleCount
            )
            
            for i in 0..<particleCount {
                updateParticlePhysics(bufferPointer: bufferPointer, index: i, deltaTime: deltaTime)
            }
        }
    }
    
    private func updateParticlePhysics(
        bufferPointer: UnsafeMutablePointer<Particle>,
        index: Int,
        deltaTime: Float
    ) {
        var particle = bufferPointer[index]
        
        // Обновляем позицию
        particle.position.x += particle.velocity.x * deltaTime
        particle.position.y += particle.velocity.y * deltaTime
        
        // Ограничение границами
        particle.position.x = clamp(
            particle.position.x,
            min: NDCBounds.minWithPadding,
            max: NDCBounds.maxWithPadding
        )
        particle.position.y = clamp(
            particle.position.y,
            min: NDCBounds.minWithPadding,
            max: NDCBounds.maxWithPadding
        )
        
        // Обработка столкновений с границами
        handleBoundaryCollisions(particle: &particle)
        
        // Защита от залипания
        preventStuckParticles(particle: &particle)
        
        bufferPointer[index] = particle
    }
    
    private func handleBoundaryCollisions(particle: inout Particle) {
        if particle.position.x <= NDCBounds.minWithPadding ||
           particle.position.x >= NDCBounds.maxWithPadding {
            particle.velocity.x *= Constants.velocityReboundFactor
        }
        
        if particle.position.y <= NDCBounds.minWithPadding ||
           particle.position.y >= NDCBounds.maxWithPadding {
            particle.velocity.y *= Constants.velocityReboundFactor
        }
    }
    
    private func preventStuckParticles(particle: inout Particle) {
        if simd.length(particle.velocity) < Constants.minVelocityThreshold {
            particle.velocity = SIMD3<Float>(
                Float.random(in: -Constants.randomImpulseRange...Constants.randomImpulseRange),
                Float.random(in: -Constants.randomImpulseRange...Constants.randomImpulseRange),
                0
            )
        }
    }
    
    func updateHighQualityTransition(deltaTime: Float) {
        bufferQueue.sync {
            performHighQualityTransition(deltaTime: deltaTime)
        }
    }
    
    private func performHighQualityTransition(deltaTime: Float) {
        let count = min(particleCount, imageTargets.count)
        guard count > 0, let particleBuffer = particleBuffer else {
            logger.warning("No high quality particles or buffer for transition")
            return
        }
        
        let lerpFactor = calculateLerpFactor(deltaTime: deltaTime)
        
        let bufferPointer = particleBuffer.contents().bindMemory(
            to: Particle.self,
            capacity: particleCount
        )
        
        for i in 0..<count {
            interpolateParticle(
                bufferPointer: bufferPointer,
                index: i,
                target: imageTargets[i],
                lerpFactor: lerpFactor
            )
        }
    }
    
    private func calculateLerpFactor(deltaTime: Float) -> Float {
        let lerpFactor = min(1.0, Constants.lerpSpeed * deltaTime)
        transitionProgress = min(1.0, transitionProgress + lerpFactor)
        return lerpFactor
    }
    
    private func interpolateParticle(
        bufferPointer: UnsafeMutablePointer<Particle>,
        index: Int,
        target: Particle,
        lerpFactor: Float
    ) {
        var current = bufferPointer[index]
        
        // Интерполяция полей
        current.position += (target.position - current.position) * lerpFactor
        current.velocity += (target.velocity - current.velocity) * lerpFactor
        current.targetPosition += (target.targetPosition - current.targetPosition) * lerpFactor
        current.color += (target.color - current.color) * lerpFactor
        current.originalColor += (target.originalColor - current.originalColor) * lerpFactor
        current.size += (target.size - current.size) * lerpFactor
        current.baseSize += (target.baseSize - current.baseSize) * lerpFactor
        current.life += (target.life - current.life) * lerpFactor
        
        // idleChaoticMotion - uint, не интерполируется
        if lerpFactor >= Constants.lerpThreshold {
            current.idleChaoticMotion = target.idleChaoticMotion
        }
        
        bufferPointer[index] = current
    }
    
    // MARK: - Cleanup
    
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
    
    // MARK: - State Access
    
    func getTransitionProgress() -> Float {
        bufferQueue.sync { transitionProgress }
    }
    
    func saveHighQualityPixels(from particles: [Particle]) {
        bufferQueue.sync {
            sourcePixels = convertParticlesToPixels(particles)
            logger.info("Saved high-quality pixels for collection")
        }
    }
    
    private func convertParticlesToPixels(_ particles: [Particle]) -> [Pixel] {
        return particles.map { particle in
            let screenCoords = ndcToScreen(particle.position)
            return Pixel(
                x: Int(screenCoords.x.rounded()),
                y: Int(screenCoords.y.rounded()),
                r: UInt8(clamping: Int((particle.color.x * 255).rounded())),
                g: UInt8(clamping: Int((particle.color.y * 255).rounded())),
                b: UInt8(clamping: Int((particle.color.z * 255).rounded())),
                a: UInt8(clamping: Int((particle.color.w * 255).rounded()))
            )
        }
    }
    
    private func ndcToScreen(_ ndcPosition: SIMD3<Float>) -> (x: Float, y: Float) {
        let screenX = (ndcPosition.x + 1.0) * 0.5 * viewWidth
        let screenY = (ndcPosition.y + 1.0) * 0.5 * viewHeight
        return (screenX, screenY)
    }
    
    // MARK: - Particle Updates
    
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
            
            let bufferPointer = particleBuffer.contents().bindMemory(
                to: Particle.self,
                capacity: particleCount
            )
            
            for (i, particle) in particles.enumerated() {
                bufferPointer[startIndex + i] = particle
            }
        }
    }
    
    // MARK: - High Quality Generation
    
    func generateHighQualityParticles(completion: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            let shouldSkip = self.bufferQueue.sync { () -> Bool in
                if !self.imageTargets.isEmpty {
                    return true
                }
                
                self.generateImageTargets()
                return false
            }
            
            if shouldSkip {
                self.logger.info("High quality targets already set - skipping generation")
            }
            
            DispatchQueue.main.async {
                completion()
            }
        }
    }
    
    private func generateImageTargets() {
        imageTargets = []
        imageTargets.reserveCapacity(particleCount)
        
        if !sourcePixels.isEmpty {
            generateTargetsFromSource()
        } else {
            generateRandomTargets()
        }
        
        transitionProgress = 0
        logger.info("High quality particles generated")
    }
    
    private func generateTargetsFromSource() {
        let count = min(particleCount, sourcePixels.count)
        
        for i in 0..<count {
            let px = sourcePixels[i]
            let pos = normalizePixelToNDC(px, viewWidth: viewWidth, viewHeight: viewHeight)
            let color = pixelToColor(px)
            let particle = createNDCParticle(
                x: pos.x,
                y: pos.y,
                color: color,
                size: Constants.highQualityParticleSize
            )
            imageTargets.append(particle)
        }
        
        for _ in count..<particleCount {
            let particle = createRandomNDCParticle()
            imageTargets.append(particle)
        }
    }
    
    private func generateRandomTargets() {
        for _ in 0..<particleCount {
            let particle = createRandomNDCParticle()
            imageTargets.append(particle)
        }
    }
    
    private func createRandomNDCParticle() -> Particle {
        let randX = Float.random(in: NDCBounds.min...NDCBounds.max)
        let randY = Float.random(in: NDCBounds.min...NDCBounds.max)
        let color = randomSourceColor()
        return createNDCParticle(
            x: randX,
            y: randY,
            color: color,
            size: Constants.highQualityParticleSize
        )
    }
}
