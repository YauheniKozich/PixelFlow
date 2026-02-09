//
//  MetalRenderer.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Metal рендерер для системы частиц
//

import Foundation
import Metal
import MetalKit
import CoreGraphics
import QuartzCore

#if canImport(ParticleSimulation)
import ParticleSimulation
#endif

// MARK: - Metal Renderer

final class MetalRenderer: NSObject, MTKViewDelegate {
    
    // MARK: - Constants
    
    private enum Constants {
        static let defaultThreadsPerThreadgroup: UInt32 = 256
        static let defaultDisplayScale: Float = 1.0
        static let defaultFPS = 60
        static let collectionProgressLogThreshold: Float = 0.05
        static let expectedSimulationParamsStride = 272
    }
    
    private enum ShaderNames {
        static let updateParticles = "updateParticles"
        static let vertexParticle = "vertexParticle"
        static let fragmentParticle = "fragmentParticle"
    }
    
    // MARK: - Dependencies
    
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let logger: LoggerProtocol
    
    // MARK: - Metal Resources
    
    var renderPipeline: MTLRenderPipelineState?
    var computePipeline: MTLComputePipelineState?
    private var threadsPerThreadgroup: UInt32 = Constants.defaultThreadsPerThreadgroup
    
    var particleBuffer: MTLBuffer?
    var paramsBuffer: MTLBuffer?
    var collectedCounterBuffer: MTLBuffer?
    private var collectedCounterPointer: UnsafeMutablePointer<UInt32>?
    
    // MARK: - State
    
    private weak var mtkView: MTKView?
    private var particleCount: Int = 0
    internal var screenSize: CGSize = .zero
    private var currentConfig: ParticleGenerationConfig = .standard
    private var enableIdleChaotic: Bool = false
    private var displayScale: Float = Constants.defaultDisplayScale
    
    private weak var simulationEngine: SimulationEngineProtocol?
    private var paramsUpdater: SimulationParamsUpdater?
    
    // MARK: - Frame Tracking
    
    private var frameCounter: Int = 0
    private var lastFrameTimestamp: CFTimeInterval = 0
    private var lastLoggedCollectionProgress: Float = 0
    
    // MARK: - Synchronization
    
    private let collectionProgressQueue = DispatchQueue(label: "com.particle.collection.progress")
    
    // MARK: - Initialization
    
    init(device: MTLDevice, logger: LoggerProtocol) throws {
        self.device = device
        
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalError.libraryCreationFailed
        }
        
        self.commandQueue = commandQueue
        self.logger = logger
        
        super.init()
        
        self.paramsUpdater = SimulationParamsUpdater()
        logger.info("MetalRenderer initialized with device: \(device.name)")
    }
    
    // MARK: - View Configuration
    
    func configureView(_ view: MTKView) throws {
        view.device = device
        view.delegate = self
        self.mtkView = view
        
        configureViewSettings(view)
        updateScreenMetrics(view)
        
        try setupPipelines()
    }
    
    private func configureViewSettings(_ view: MTKView) {
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = true
        view.preferredFramesPerSecond = Constants.defaultFPS
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false
    }
    
    private func updateScreenMetrics(_ view: MTKView) {
        screenSize = view.drawableSize
        displayScale = calculateDisplayScale(view)
    }
    
    private func calculateDisplayScale(_ view: MTKView) -> Float {
        guard view.bounds.width > 0 else {
            return Constants.defaultDisplayScale
        }
        return Float(view.drawableSize.width / view.bounds.width)
    }
    
    // MARK: - Pipeline Setup
    
    func setupPipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw MetalError.libraryCreationFailed
        }
        
        try setupComputePipeline(library: library)
        try setupRenderPipeline(library: library)
        
        validateStructLayouts()
        logger.info("Metal pipelines setup completed")
    }
    
    private func setupComputePipeline(library: MTLLibrary) throws {
        guard let computeFunction = library.makeFunction(name: ShaderNames.updateParticles) else {
            throw MetalError.functionNotFound(name: ShaderNames.updateParticles)
        }
        
        let pipeline = try device.makeComputePipelineState(function: computeFunction)
        computePipeline = pipeline
        threadsPerThreadgroup = UInt32(pipeline.threadExecutionWidth)
    }
    
    private func setupRenderPipeline(library: MTLLibrary) throws {
        let descriptor = try createRenderPipelineDescriptor(library: library)
        configureBlending(descriptor: descriptor)
        renderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
    }
    
    private func createRenderPipelineDescriptor(library: MTLLibrary) throws -> MTLRenderPipelineDescriptor {
        let descriptor = MTLRenderPipelineDescriptor()
        
        guard let vertexFunction = library.makeFunction(name: ShaderNames.vertexParticle),
              let fragmentFunction = library.makeFunction(name: ShaderNames.fragmentParticle) else {
            throw MetalError.functionNotFound(
                name: "\(ShaderNames.vertexParticle)/\(ShaderNames.fragmentParticle)"
            )
        }
        
        descriptor.vertexFunction = vertexFunction
        descriptor.fragmentFunction = fragmentFunction
        descriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb
        
        return descriptor
    }
    
    private func configureBlending(descriptor: MTLRenderPipelineDescriptor) {
        guard let attachment = descriptor.colorAttachments[0] else { return }
        
        attachment.isBlendingEnabled = true
        attachment.rgbBlendOperation = .add
        attachment.alphaBlendOperation = .add
        attachment.sourceRGBBlendFactor = .sourceAlpha
        attachment.sourceAlphaBlendFactor = .sourceAlpha
        attachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
        attachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
    }
    
    private func validateStructLayouts() {
        let stride = MemoryLayout<SimulationParams>.stride
        precondition(
            stride == Constants.expectedSimulationParamsStride,
            "SimulationParams layout changed – stride \(stride)"
        )
    }
    
    // MARK: - Buffers
    
    func setupBuffers(particleCount: Int) throws {
        // Очищаем старые буферы перед созданием новых
        cleanupBuffers()
        
        self.particleCount = particleCount
        
        guard let newParticleBuffer = device.makeBuffer(
            length: MemoryLayout<Particle>.stride * particleCount,
            options: .storageModeShared
        ) else {
            throw MetalError.bufferCreationFailed
        }
        
        guard let newParamsBuffer = device.makeBuffer(
            length: MemoryLayout<SimulationParams>.stride,
            options: .storageModeShared
        ) else {
            throw MetalError.bufferCreationFailed
        }
        
        guard let newCollectedCounterBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        ) else {
            throw MetalError.bufferCreationFailed
        }
        
        particleBuffer = newParticleBuffer
        paramsBuffer = newParamsBuffer
        collectedCounterBuffer = newCollectedCounterBuffer
        
        collectedCounterPointer = newCollectedCounterBuffer.contents().assumingMemoryBound(to: UInt32.self)
    }
    
    private func cleanupBuffers() {
        particleBuffer = nil
        paramsBuffer = nil
        collectedCounterBuffer = nil
        collectedCounterPointer = nil
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        screenSize = size
        displayScale = calculateDisplayScale(view)
        updateSimulationParams()
    }
    
    func draw(in view: MTKView) {
        guard shouldRender(view: view),
              particleCount > 0,
              validateRenderingResources(view: view) else {
            return
        }
        
        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }
        
        let dt = calculateDeltaTime(view: view)
        simulationEngine?.update(deltaTime: Float(dt))
        
        updateSimulationParams()
        encodeCompute(into: commandBuffer)
        encodeRender(into: commandBuffer, view: view)
        
        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkCollectionCompletion()
            }
        }
        
        if let drawable = view.currentDrawable {
            commandBuffer.present(drawable)
        }
        
        commandBuffer.commit()
        frameCounter += 1
    }
    
    private func shouldRender(view: MTKView) -> Bool {
        view.bounds.width > 0 && view.bounds.height > 0 && !view.isHidden
    }
    
    private func validateRenderingResources(view: MTKView) -> Bool {
        view.currentDrawable != nil &&
        view.currentRenderPassDescriptor != nil &&
        renderPipeline != nil &&
        particleBuffer != nil &&
        paramsBuffer != nil &&
        collectedCounterBuffer != nil
    }
    
    private func calculateDeltaTime(view: MTKView) -> CFTimeInterval {
        let now = CACurrentMediaTime()
        defer { lastFrameTimestamp = now } // всегда обновляем
        
        guard lastFrameTimestamp > 0 else {
            return 1.0 / Double(max(1, view.preferredFramesPerSecond))
        }
        
        let dt = now - lastFrameTimestamp
        return min(max(dt, 0), 0.1) // также ограничиваем минимальное значение
    }
    
    // MARK: - Simulation Params
    
    @MainActor
    func updateSimulationParams() {
        guard let updater = paramsUpdater,
              let buffer = paramsBuffer,
              let engine = simulationEngine else { return }
        
        let safeSize = screenSize.width > 0 ? screenSize : CGSize(width: 1, height: 1)
        
        updater.fill(
            buffer: buffer,
            state: engine.state,
            clock: engine.clock,
            screenSize: safeSize,
            particleCount: particleCount,
            config: currentConfig,
            enableIdleChaotic: enableIdleChaotic,
            displayScale: displayScale,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
    }
    
    // MARK: - Compute / Render
    
    func encodeCompute(into commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder(),
              let pipeline = computePipeline else { return }
        
        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 1)
        encoder.setBuffer(collectedCounterBuffer, offset: 0, index: 2)
        
        let w = pipeline.threadExecutionWidth
        let groups = (particleCount + w - 1) / w
        
        encoder.dispatchThreadgroups(
            MTLSize(width: groups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )
        
        encoder.endEncoding()
    }
    
    private func encodeRender(into commandBuffer: MTLCommandBuffer, view: MTKView) {
        guard let desc = view.currentRenderPassDescriptor,
              let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: desc),
              let pipeline = renderPipeline else { return }
        
        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(paramsBuffer, offset: 0, index: 1)
        encoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
        encoder.endEncoding()
    }
    
    // MARK: - GPU Sync
    
    private func waitForGPUIdle() {
        guard let buffer = commandQueue.makeCommandBuffer() else { return }
        buffer.commit()
        buffer.waitUntilCompleted()
    }
}

// MARK: - MetalRendererProtocol

extension MetalRenderer: MetalRendererProtocol {
    
    func cleanup() {
        logger.info("MetalRenderer cleanup started")
        
        waitForGPUIdle()
        
        cleanupBuffers()
        
        particleCount = 0
        frameCounter = 0
        lastFrameTimestamp = 0
        lastLoggedCollectionProgress = 0
        simulationEngine = nil
        
        logger.info("MetalRenderer cleanup completed")
    }
    
    func setParticleBuffer(_ buffer: MTLBuffer?) {
        waitForGPUIdle()
        particleBuffer = buffer
    }
    
    func updateParticleCount(_ count: Int) {
        guard count >= 0 else {
            logger.error("Invalid particle count: \(count)")
            return
        }
        
        waitForGPUIdle()
        particleCount = count
        resetCollectedCounter()
    }
    
    func setSimulationEngine(_ engine: SimulationEngineProtocol) {
        simulationEngine = engine
        resetCollectedCounter()
        
        Task { @MainActor [weak self] in
            self?.updateSimulationParams()
        }
    }
    
    func resetCollectedCounter() {
        collectionProgressQueue.async { [weak self] in
            guard let self = self,
                  let ptr = self.collectedCounterPointer else { return }
            ptr.pointee = 0
            self.lastLoggedCollectionProgress = 0
        }
    }
    
    func checkCollectionCompletion() {
        guard let engine = simulationEngine,
              particleCount > 0,
              let ptr = collectedCounterPointer else { return }
        
        let collected = Int(ptr.pointee)
        let ratio = min(1, Float(collected) / Float(particleCount))
        
        // Проверяем состояние в основном потоке
        Task { @MainActor in
            guard case .collecting = engine.state else { return }
            
            if ratio - lastLoggedCollectionProgress >= Constants.collectionProgressLogThreshold || ratio >= 1 {
                lastLoggedCollectionProgress = ratio
                logger.info("Collection progress: \(Int(ratio * 100))% (\(collected)/\(particleCount))")
            }
            
            engine.updateProgress(ratio)
        }
    }
}
