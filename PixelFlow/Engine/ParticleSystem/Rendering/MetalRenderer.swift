//
//  MetalRenderer.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Metal рендерер для системы частиц
//

@preconcurrency import Metal
import MetalKit
import CoreGraphics
import QuartzCore

#if canImport(ParticleSimulation)
import ParticleSimulation
#endif

final class MetalRenderer: NSObject, MTKViewDelegate {

    // MARK: - Зависимости
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let logger: LoggerProtocol

    // MARK: - Metal Ресурсы
    var renderPipeline: MTLRenderPipelineState?
    var computePipeline: MTLComputePipelineState?
    private var threadsPerThreadgroup: UInt32 = 256

    var particleBuffer: MTLBuffer?
    var paramsBuffer: MTLBuffer?
    var collectedCounterBuffer: MTLBuffer?

    // MARK: - Состояние
    private weak var mtkView: MTKView?
    private var particleCount: Int = 0
    internal var screenSize: CGSize = .zero
    private var currentConfig: ParticleGenerationConfig = .standard
    private var enableIdleChaotic: Bool = false
    private var displayScale: Float = 1.0

    private weak var simulationEngine: SimulationEngineProtocol?
    private var paramsUpdater: SimulationParamsUpdater?

    private var frameCounter: Int = 0
    private var updateCounter: Int = 0
    private var firstDraw: Bool = true
    // Reserved for future detailed diagnostics
    private var lastFrameTimestamp: CFTimeInterval = 0

    // MARK: - Инициализация
    init(device: MTLDevice, logger: LoggerProtocol) throws {
        self.device = device
        guard let commandQueue = device.makeCommandQueue() else {
            throw MetalError.libraryCreationFailed
        }
        self.commandQueue = commandQueue
        self.logger = logger
        self.screenSize = CGSize(width: 375, height: 812)
        super.init()
        self.paramsUpdater = SimulationParamsUpdater()
        logger.info("MetalRenderer initialized with device: \(device.name)")
    }

    // MARK: - MTKView Конфигурация
    func configureView(_ view: MTKView) throws {
        view.device = device
        view.delegate = self
        self.mtkView = view
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.isPaused = false
        view.enableSetNeedsDisplay = false

        self.screenSize = view.drawableSize
        self.displayScale = view.bounds.width > 0 ? Float(view.drawableSize.width / view.bounds.width) : 1.0

        try setupPipelines()
    }

    // MARK: - Pipeline Установка
    func setupPipelines() throws {
        guard let library = device.makeDefaultLibrary() else {
            throw MetalError.libraryCreationFailed
        }

        // Compute pipeline
        guard let computeFunction = library.makeFunction(name: "updateParticles") else {
            throw MetalError.functionNotFound(name: "updateParticles")
        }
        computePipeline = try device.makeComputePipelineState(function: computeFunction)
        threadsPerThreadgroup = UInt32(computePipeline!.threadExecutionWidth)

        // Render pipeline
        let renderDescriptor = MTLRenderPipelineDescriptor()
        guard let vertexFunction = library.makeFunction(name: "vertexParticle"),
              let fragmentFunction = library.makeFunction(name: "fragmentParticle") else {
            throw MetalError.functionNotFound(name: "vertexParticle/fragmentParticle")
        }
        renderDescriptor.vertexFunction = vertexFunction
        renderDescriptor.fragmentFunction = fragmentFunction
        renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb

        if let colorAttachment = renderDescriptor.colorAttachments[0] {
            colorAttachment.isBlendingEnabled = true
            colorAttachment.rgbBlendOperation = .add
            colorAttachment.alphaBlendOperation = .add
            colorAttachment.sourceRGBBlendFactor = .sourceAlpha
            colorAttachment.sourceAlphaBlendFactor = .sourceAlpha
            colorAttachment.destinationRGBBlendFactor = .oneMinusSourceAlpha
            colorAttachment.destinationAlphaBlendFactor = .oneMinusSourceAlpha
        }

        renderPipeline = try device.makeRenderPipelineState(descriptor: renderDescriptor)
        validateStructLayouts()
        logger.info("Metal pipelines setup completed")
    }

    // MARK: - Буферы
    func setupBuffers(particleCount: Int) throws {
        self.particleCount = particleCount

        particleBuffer = device.makeBuffer(
            length: MemoryLayout<Particle>.stride * particleCount,
            options: .storageModeShared
        )

        paramsBuffer = device.makeBuffer(
            length: MemoryLayout<SimulationParams>.stride,
            options: .storageModeShared
        )

        collectedCounterBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )

        guard particleBuffer != nil, paramsBuffer != nil, collectedCounterBuffer != nil else {
            throw MetalError.bufferCreationFailed
        }

        logger.info("Metal buffers created successfully")
    }

    // MARK: - MTKViewDelegate
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        screenSize = size
        displayScale = view.bounds.width > 0 ? Float(size.width / view.bounds.width) : 1.0
        updateSimulationParams()
        
        // No extra logging here (keep renderer quiet)
    }

    func draw(in view: MTKView) {
        // Детальная диагностика перед рендерингом
        guard shouldRender(view: view) else { return }

        guard particleCount > 0 else { return }

        guard let drawable = view.currentDrawable else { return }

        guard let renderPassDescriptor = view.currentRenderPassDescriptor else { return }

        let now = CACurrentMediaTime()
        let fallbackFPS = view.preferredFramesPerSecond > 0 ? view.preferredFramesPerSecond : 60
        let dt = lastFrameTimestamp > 0 ? now - lastFrameTimestamp : 1.0 / Double(fallbackFPS)
        lastFrameTimestamp = now
        simulationEngine?.update(deltaTime: Float(dt))

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        guard let renderPipeline = renderPipeline else { return }

        // Проверка буферов перед использованием
        guard let particleBuffer = particleBuffer else { return }
        guard let paramsBuffer = paramsBuffer else { return }
        guard let collectedCounterBuffer = collectedCounterBuffer else { return }

        updateSimulationParams()
        encodeCompute(into: commandBuffer)

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else { return }

        renderEncoder.setRenderPipelineState(renderPipeline)
        renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(paramsBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 1)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        frameCounter += 1
        updateCounter += 1
        firstDraw = false
    }

    // MARK: - Simulation Params
    @MainActor func updateSimulationParams() {
        guard let paramsUpdater = paramsUpdater,
              let paramsBuffer = paramsBuffer,
              let simulationEngine = simulationEngine else { return }

        let safeScreenSize = screenSize.width > 0 && screenSize.height > 0
        ? screenSize
        : CGSize(width: 1, height: 1)

        paramsUpdater.fill(
            buffer: paramsBuffer,
            state: simulationEngine.state,
            clock: simulationEngine.clock,
            screenSize: safeScreenSize,
            particleCount: particleCount,
            config: currentConfig,
            enableIdleChaotic: enableIdleChaotic,
            displayScale: displayScale,
            threadsPerThreadgroup: threadsPerThreadgroup
        )
    }

    // MARK: - Compute
    func encodeCompute(into commandBuffer: MTLCommandBuffer) {
        guard let encoder = commandBuffer.makeComputeCommandEncoder(),
              let computePipeline = computePipeline else { return }

        encoder.setComputePipelineState(computePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 1)
        encoder.setBuffer(collectedCounterBuffer, offset: 0, index: 2)

        let w = computePipeline.threadExecutionWidth
        let threadgroups = MTLSize(width: (particleCount + w - 1) / w, height: 1, depth: 1)
        let threadsPerThreadgroup = MTLSize(width: w, height: 1, depth: 1)

        encoder.dispatchThreadgroups(threadgroups, threadsPerThreadgroup: threadsPerThreadgroup)
        encoder.endEncoding()
    }

    // MARK: - Utilities
    private func shouldRender(view: MTKView) -> Bool {
        view.bounds.width > 0 && view.bounds.height > 0 && !view.isHidden
    }

    private func validateStructLayouts() {
        let simParamsStride = MemoryLayout<SimulationParams>.stride
        assert(simParamsStride == 272, "SimulationParams layout changed - stride \(simParamsStride)")
    }
}

// MARK: - MetalRendererProtocol
extension MetalRenderer: MetalRendererProtocol {

    func resetCollectedCounter() {
        guard let collectedCounterBuffer = collectedCounterBuffer else { return }
        collectedCounterBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee = 0
    }

    func checkCollectionCompletion() {
        guard let collectedCounterBuffer = collectedCounterBuffer,
              let engine = simulationEngine else { return }

        guard case .collecting = engine.state else { return }
        guard particleCount > 0 else { return }

        let collectedCount = Int(collectedCounterBuffer.contents().assumingMemoryBound(to: UInt32.self).pointee)
        let completionRatio = Float(collectedCount) / Float(particleCount)
        engine.updateProgress(completionRatio)
    }

    func cleanup() {
        renderPipeline = nil
        computePipeline = nil
        particleBuffer = nil
        paramsBuffer = nil
        collectedCounterBuffer = nil

        frameCounter = 0
        updateCounter = 0
        firstDraw = true
        lastFrameTimestamp = 0
    }

    func setParticleBuffer(_ buffer: MTLBuffer?) {
        if let buffer = buffer, buffer.length >= particleCount * MemoryLayout<Particle>.stride {
            particleBuffer = buffer
            logger.debug("Particle buffer set with \(particleCount) particles")
        }
    }

    func updateParticleCount(_ count: Int) {
        particleCount = count
    }

    func setSimulationEngine(_ engine: SimulationEngineProtocol) {
        simulationEngine = engine
        if let view = mtkView {
            updateSimulationParams()
            view.draw() // гарантированный первый кадр
        }
    }

    func setEnableIdleChaotic(_ enabled: Bool) {
        enableIdleChaotic = enabled
    }
}
