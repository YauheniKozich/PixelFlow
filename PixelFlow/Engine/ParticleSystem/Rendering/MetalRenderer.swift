//
//  MetalRenderer.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Metal рендерер для системы частиц
//

import Metal
import MetalKit
import CoreGraphics

/// Metal рендерер для системы частиц
final class MetalRenderer: NSObject, MetalRendererProtocol, MTKViewDelegate {

    // MARK: - Dependencies

    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    private let logger: LoggerProtocol

    // MARK: - Metal Resources

    var renderPipeline: MTLRenderPipelineState?
    var computePipeline: MTLComputePipelineState?

    var particleBuffer: MTLBuffer?
    var paramsBuffer: MTLBuffer?
    var collectedCounterBuffer: MTLBuffer?

    // MARK: - State

    private var particleCount: Int = 0
    private var screenSize: CGSize = .zero
    private var currentConfig: ParticleGenerationConfig = .standard

    private weak var simulationEngine: SimulationEngineProtocol?
    private var paramsUpdater: SimulationParamsUpdater?

    // MARK: - Initialization

    init(device: MTLDevice = MTLCreateSystemDefaultDevice()!,
         logger: LoggerProtocol = Logger.shared) {
        self.device = device
        self.commandQueue = device.makeCommandQueue()!
        self.logger = logger

        super.init()

        self.paramsUpdater = SimulationParamsUpdater()
        logger.info("MetalRenderer initialized with device: \(device.name)")
    }

    // MARK: - MetalRendererProtocol

    func setupPipelines() throws {
        logger.debug("Setting up Metal pipelines")

        guard let library = device.makeDefaultLibrary() else {
            throw MetalError.libraryCreationFailed
        }

        // Compute pipeline для обновления частиц
        guard let computeFunction = library.makeFunction(name: "updateParticles") else {
            throw MetalError.functionNotFound(name: "updateParticles")
        }

        computePipeline = try device.makeComputePipelineState(function: computeFunction)

        // Render pipeline для рисования частиц
        let renderDescriptor = MTLRenderPipelineDescriptor()

        guard let vertexFunction = library.makeFunction(name: "vertexParticle"),
              let fragmentFunction = library.makeFunction(name: "fragmentParticle") else {
            throw MetalError.functionNotFound(name: "vertexParticle/fragmentParticle")
        }

        renderDescriptor.vertexFunction = vertexFunction
        renderDescriptor.fragmentFunction = fragmentFunction
        renderDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm_srgb

        // Настройка blending
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

    func setupBuffers(particleCount: Int) throws {
        logger.debug("Setting up Metal buffers for \(particleCount) particles")

        self.particleCount = particleCount

        // Only create particleBuffer if not already set externally
        if particleBuffer == nil {
            particleBuffer = device.makeBuffer(
                length: MemoryLayout<Particle>.stride * particleCount,
                options: .storageModeShared
            )
        }

        paramsBuffer = device.makeBuffer(
            length: MemoryLayout<SimulationParams>.stride,
            options: .storageModeShared
        )

        collectedCounterBuffer = device.makeBuffer(
            length: MemoryLayout<UInt32>.stride,
            options: .storageModeShared
        )

        guard paramsBuffer != nil, collectedCounterBuffer != nil else {
            throw MetalError.bufferCreationFailed
        }

        // particleBuffer might be set externally, so we don't require it here

        logger.info("Metal buffers setup completed")
    }

    func updateSimulationParams() {
        guard let paramsUpdater = paramsUpdater,
              let paramsBuffer = paramsBuffer,
              let simulationEngine = simulationEngine else {
            logger.warning("Cannot update simulation params - missing dependencies")
            return
        }

        // Note: Need to fix state and clock types
        // paramsUpdater.fill(
        //     buffer: paramsBuffer,
        //     state: simulationEngine.stateMachine.currentState,
        //     clock: simulationEngine.clock as! SimulationClock,
        //     screenSize: screenSize,
        //     particleCount: particleCount,
        //     config: currentConfig
        // )
    }

    func resetCollectedCounter() {
        guard let collectedCounterBuffer = collectedCounterBuffer else {
            logger.warning("Cannot reset collected counter - buffer not available")
            return
        }

        collectedCounterBuffer
            .contents()
            .assumingMemoryBound(to: UInt32.self)
            .pointee = 0
    }

    func checkCollectionCompletion() {
        guard let collectedCounterBuffer = collectedCounterBuffer,
              let simulationEngine = simulationEngine else {
            return
        }

        guard case .collecting = simulationEngine.state else { return }

        let counterPtr = collectedCounterBuffer.contents().assumingMemoryBound(to: UInt32.self)
        let collectedCount = Int(counterPtr.pointee)
        let completionRatio = Float(collectedCount) / Float(particleCount)

        simulationEngine.updateProgress(completionRatio)
    }

    func cleanup() {
        logger.info("Cleaning up Metal resources")

        renderPipeline = nil
        computePipeline = nil
        particleBuffer = nil
        paramsBuffer = nil
        collectedCounterBuffer = nil

        logger.info("Metal resources cleaned up")
    }

    // MARK: - Public Methods

    func configureView(_ view: MTKView) {
        logger.debug("Configuring MTKView")

        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60

        // Отключаем автоматический рендеринг
        view.isPaused = true
        view.enableSetNeedsDisplay = false
    }

    func updateConfiguration(_ config: ParticleGenerationConfig, screenSize: CGSize) {
        self.currentConfig = config
        self.screenSize = screenSize
    }

    func setSimulationEngine(_ engine: SimulationEngineProtocol) {
        self.simulationEngine = engine
    }

    func setParticleBuffer(_ buffer: MTLBuffer?) {
        self.particleBuffer = buffer
        logger.debug("Particle buffer set from external source")
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        screenSize = size
        logger.debug("MTKView drawable size changed to: \(size)")
    }

    func draw(in view: MTKView) {
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            logger.warning("Cannot draw - missing Metal resources")
            return
        }

        // Обновляем параметры симуляции
        updateSimulationParams()

        // Настраиваем render encoder
        renderEncoder.setRenderPipelineState(renderPipeline!)
        renderEncoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        renderEncoder.setVertexBuffer(paramsBuffer, offset: 0, index: 1)
        renderEncoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 1)

        // Рисуем частицы (point primitives)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)

        renderEncoder.endEncoding()

        commandBuffer.present(drawable)
        commandBuffer.commit()

        // Проверяем завершение сбора частиц
        checkCollectionCompletion()
    }

    // MARK: - Private Methods

    private func validateStructLayouts() {
        assert(MemoryLayout<SimulationParams>.stride == 256, "SimulationParams layout changed")
        assert(MemoryLayout<Particle>.stride % 16 == 0, "Particle layout not aligned to 16 bytes")
        logger.debug("Struct layouts validated")
    }
}

// MARK: - Errors

enum MetalError: Error {
    case libraryCreationFailed
    case functionNotFound(name: String)
    case bufferCreationFailed
    case pipelineCreationFailed

    var localizedDescription: String {
        switch self {
        case .libraryCreationFailed:
            return "Не удалось создать Metal library"
        case .functionNotFound(let name):
            return "Функция '\(name)' не найдена в Metal library"
        case .bufferCreationFailed:
            return "Не удалось создать Metal буферы"
        case .pipelineCreationFailed:
            return "Не удалось создать Metal pipeline"
        }
    }
}