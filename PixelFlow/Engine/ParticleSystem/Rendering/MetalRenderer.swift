//
//  MetalRenderer.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Metal рендерер для системы частиц
//

// swiftlint:disable identifier_name
// Graphics code uses short variable names for mathematical readability

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
        // 272 bytes — SimulationParams layout (согласовано с Simulation.h)
        // Включает: state, time, deltaTime, screenSize, particleCount, и др.
        static let expectedSimulationParamsStride = 272
        static let maxDeltaTime: CFTimeInterval = 0.1 // 100ms cap для предотвращения spiral of death
        static let fallbackFrameDuration = 1.0 / Double(defaultFPS)
    }
    
    private enum ShaderNames {
        static let updateParticles = "updateParticles"
        static let vertexParticle = "vertexParticle"
        static let fragmentParticle = "fragmentParticle"
        static let fragmentParticlePerformance = "fragmentParticlePerformance"
    }
    
    // MARK: - Dependencies

    private let _device: MTLDevice
    private let _commandQueue: MTLCommandQueue
    private let logger: LoggerProtocol

    // MARK: - Protocol Exposed Dependencies

    /// Устройство Metal (для протокола)
    var device: MTLDevice { _device }

    /// Очередь команд Metal (для протокола)
    var commandQueue: MTLCommandQueue { _commandQueue }

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
    private(set) var screenSize: CGSize = .zero
    private var currentConfig: ParticleGenerationConfig = .standard
    private var renderQuality: RenderQuality = .standard
    private var enableIdleChaotic: Bool = false
    private var displayScale: Float = Constants.defaultDisplayScale

    private weak var simulationEngine: SimulationEngineProtocol?
    private var paramsUpdater: SimulationParamsUpdater?
    private var shaderLibrary: MTLLibrary?
    
    // MARK: - Frame Tracking

    private var lastFrameTimestamp: CFTimeInterval = 0
    private var lastLoggedCollectionProgress: Float = 0
    private var isPipelineConfigured: Bool = false

    // MARK: - Synchronization

    // Сериальная очередь для синхронизации доступа к collectedCounterPointer
    private let counterAccessQueue = DispatchQueue(
        label: "com.pixelflow.counter.access",
        qos: .userInitiated
    )
    
    // MARK: - Initialization
    
    init(device: MTLDevice, logger: LoggerProtocol) throws {
        self._device = device

        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalError.commandQueueCreationFailed
        }

        self._commandQueue = commandQueue
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
        guard !isPipelineConfigured else {
            logger.warning("Pipelines already configured — skipping")
            return
        }

        guard let library = device.makeDefaultLibrary() else {
            throw MetalError.libraryCreationFailed
        }
        shaderLibrary = library

        try setupComputePipeline(library: library)
        try setupRenderPipeline(library: library)
        try validateStructLayouts()

        isPipelineConfigured = true
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
        let fragmentFunctionName: String

        switch renderQuality {
        case .standard:
            fragmentFunctionName = ShaderNames.fragmentParticle
        case .performance:
            fragmentFunctionName = ShaderNames.fragmentParticlePerformance
        }
        
        guard let vertexFunction = library.makeFunction(name: ShaderNames.vertexParticle),
              let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            throw MetalError.functionNotFound(
                name: "\(ShaderNames.vertexParticle)/\(fragmentFunctionName)"
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
    
    private func validateStructLayouts() throws {
        let stride = MemoryLayout<SimulationParams>.stride

        #if DEBUG
        assert(
            stride == Constants.expectedSimulationParamsStride,
            "SimulationParams layout changed – stride \(stride), expected \(Constants.expectedSimulationParamsStride)"
        )
        #endif

        guard stride == Constants.expectedSimulationParamsStride else {
            throw MetalError.structLayoutMismatch(
                actual: stride,
                expected: Constants.expectedSimulationParamsStride
            )
        }
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
        // Сначала обнуляем pointer под защитой очереди
        counterAccessQueue.sync {
            collectedCounterPointer = nil
        }

        particleBuffer = nil
        paramsBuffer = nil
        collectedCounterBuffer = nil
    }
    
    // MARK: - MTKViewDelegate
    
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        screenSize = size
        displayScale = calculateDisplayScale(view)
        updateSimulationParams()
    }
    
    func draw(in view: MTKView) {
        guard shouldRender(view: view),
              particleCount > 0 else {
            return
        }

        // Кэшируем drawable — избегаем повторного обращения к view.currentDrawable
        guard let drawable = view.currentDrawable,
              let renderPassDesc = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let pipeline = renderPipeline,
              let particleBuf = particleBuffer,
              let paramsBuf = paramsBuffer else {
            return
        }

        let dt = calculateDeltaTime(view: view)
        simulationEngine?.update(deltaTime: Float(dt))

        updateSimulationParams()
        encodeCompute(into: commandBuffer)
        encodeRender(into: commandBuffer, renderPassDesc: renderPassDesc, pipeline: pipeline, particleBuf: particleBuf, paramsBuf: paramsBuf)

        commandBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                self?.checkCollectionCompletion()
            }
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Deinit

    deinit {
        // Safety net: предотвращает вызов delegate методов после dealloc
        // Если cleanup() не был вызван — логируем предупреждение
        if particleBuffer != nil || paramsBuffer != nil {
            logger.warning("MetalRenderer deallocated without cleanup() — GPU resources may leak")
        }
        mtkView?.delegate = nil
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
            return Constants.fallbackFrameDuration
        }

        let dt = now - lastFrameTimestamp
        return min(max(dt, 0), Constants.maxDeltaTime)
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

    /// Публичный метод для encode compute (совместимость с протоколом)
    func encodeCompute(into commandBuffer: MTLCommandBuffer) {
        guard let pipeline = computePipeline,
              let particleBuf = particleBuffer,
              let paramsBuf = paramsBuffer,
              let counterBuf = collectedCounterBuffer else { return }

        encodeComputeInternal(
            into: commandBuffer,
            pipeline: pipeline,
            particleBuf: particleBuf,
            paramsBuf: paramsBuf,
            counterBuf: counterBuf
        )
    }

    private func encodeComputeInternal(
        into commandBuffer: MTLCommandBuffer,
        pipeline: MTLComputePipelineState,
        particleBuf: MTLBuffer,
        paramsBuf: MTLBuffer,
        counterBuf: MTLBuffer
    ) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

        encoder.setComputePipelineState(pipeline)
        encoder.setBuffer(particleBuf, offset: 0, index: 0)
        encoder.setBuffer(paramsBuf, offset: 0, index: 1)
        encoder.setBuffer(counterBuf, offset: 0, index: 2)

        let w = pipeline.threadExecutionWidth
        let groups = (particleCount + w - 1) / w

        encoder.dispatchThreadgroups(
            MTLSize(width: groups, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )

        encoder.endEncoding()
    }

    private func encodeRender(
        into commandBuffer: MTLCommandBuffer,
        renderPassDesc: MTLRenderPassDescriptor,
        pipeline: MTLRenderPipelineState,
        particleBuf: MTLBuffer,
        paramsBuf: MTLBuffer
    ) {
        guard let encoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDesc) else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(particleBuf, offset: 0, index: 0)
        encoder.setVertexBuffer(paramsBuf, offset: 0, index: 1)
        encoder.setFragmentBuffer(paramsBuf, offset: 0, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
        encoder.endEncoding()
    }
}

// MARK: - MetalRendererProtocol

extension MetalRenderer: MetalRendererProtocol {

    func cleanup() {
        logger.info("MetalRenderer cleanup started")

        // Останавливаем рендеринг
        mtkView?.isPaused = true
        mtkView?.delegate = nil

        // Асинхронно ждём GPU — не блокируем @MainActor
        Task.detached(priority: .userInitiated) { [weak commandQueue] in
            guard let commandQueue = commandQueue,
                  let buffer = commandQueue.makeCommandBuffer() else { return }
            buffer.commit()
            await buffer.completed()
        }

        // Обнуляем pointer под защитой и освобождаем буферы
        counterAccessQueue.sync {
            collectedCounterPointer = nil
        }

        particleBuffer = nil
        paramsBuffer = nil
        collectedCounterBuffer = nil

        // Сбрасываем состояние
        particleCount = 0
        lastFrameTimestamp = 0
        lastLoggedCollectionProgress = 0
        isPipelineConfigured = false
        simulationEngine = nil
        shaderLibrary = nil
        renderQuality = .standard
        currentConfig = .standard

        logger.info("MetalRenderer cleanup completed")
    }

    func setParticleBuffer(_ buffer: MTLBuffer?) {
        // Вызывать только при mtkView?.isPaused = true
        // Рендеринг должен быть остановлен чтобы избежать гонки с GPU
        particleBuffer = buffer
    }

    func updateParticleCount(_ count: Int) {
        guard count >= 0 else {
            logger.error("Invalid particle count: \(count)")
            return
        }

        // Вызывать только при mtkView?.isPaused = true
        particleCount = count
        resetCollectedCounter()
    }
    
    func setSimulationEngine(_ engine: SimulationEngineProtocol) {
        simulationEngine = engine
        resetCollectedCounter()
        updateSimulationParams()
    }

    func setParticleGenerationConfig(_ config: ParticleGenerationConfig) {
        currentConfig = config
        updateSimulationParams()
    }

    func setRenderQuality(_ quality: RenderQuality) {
        guard renderQuality != quality else { return }
        renderQuality = quality

        guard isPipelineConfigured else { return }
        guard let library = shaderLibrary else {
            logger.warning("Render quality changed to \(quality) before shader library was cached")
            return
        }

        do {
            try setupRenderPipeline(library: library)
            logger.info("Render quality switched to \(quality)")
        } catch {
            logger.error("Failed to switch render quality to \(quality): \(error)")
        }
    }
    
    func resetCollectedCounter() {
        counterAccessQueue.sync {
            guard let ptr = collectedCounterPointer else { return }
            ptr.pointee = 0
            lastLoggedCollectionProgress = 0
        }
    }

    func checkCollectionCompletion() {
        // Читаем pointer под защитой очереди
        let collectedValue: Int? = counterAccessQueue.sync { [weak self] in
            guard let ptr = self?.collectedCounterPointer else { return nil }
            return Int(ptr.pointee)
        }

        guard let collected = collectedValue,
              let engine = simulationEngine,
              particleCount > 0 else { return }

        let ratio = min(1, Float(collected) / Float(particleCount))

        // Метод вызывается из DispatchQueue.main.async — уже на основном потоке
        guard case .collecting = engine.state else { return }

        if ratio - lastLoggedCollectionProgress >= Constants.collectionProgressLogThreshold || ratio >= 1 {
            lastLoggedCollectionProgress = ratio
            logger.info("Collection progress: \(Int(ratio * 100))% (\(collected)/\(particleCount))")
        }

        engine.updateProgress(ratio)
    }
}

// swiftlint:enable identifier_name
