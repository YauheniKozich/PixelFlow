//
//  ParticleSystem+MetalSetup.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit


extension ParticleSystem {
    // MARK: - Настройка Metal
    
    func configureView(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60
        
        // Отключаем автоматический рендеринг - используем CADisplayLink
        view.isPaused = true
        view.enableSetNeedsDisplay = false
    }
    
    func setupPipelines(view: MTKView) throws {
        guard let library = device.makeDefaultLibrary() else {
            throw NSError(domain: "Metal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Не удалось создать библиотеку Metal"])
        }
        
        guard let computeFunction = library.makeFunction(name: "updateParticles") else {
            throw NSError(domain: "Metal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Функция 'updateParticles' не найдена"])
        }
        
        computePipeline = try device.makeComputePipelineState(function: computeFunction)
        
        let renderDescriptor = MTLRenderPipelineDescriptor()
        
        guard let vertexFunction = library.makeFunction(name: "vertexParticle"),
              let fragmentFunction = library.makeFunction(name: "fragmentParticle") else {
            throw NSError(domain: "Metal", code: -1, userInfo: [NSLocalizedDescriptionKey: "Шейдерные функции не найдены"])
        }
        
        renderDescriptor.vertexFunction = vertexFunction
        renderDescriptor.fragmentFunction = fragmentFunction
        renderDescriptor.colorAttachments[0].pixelFormat = view.colorPixelFormat
        
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
    }
    
    func setupBuffers() throws {
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
    }
    
    func updateSimulationParams() {
        paramsUpdater.particleSystem = self
        paramsUpdater.fill(
            buffer: paramsBuffer,
            state: stateMachine.state,
            clock: clock,
            screenSize: screenSize,
            particleCount: particleCount
        )
    }
    
    func resetCollectedCounterIfNeeded() {
        collectedCounterBuffer
            .contents()
            .assumingMemoryBound(to: UInt32.self)
            .pointee = 0
    }
    
    func validateStructLayouts() {
        assert(MemoryLayout<SimulationParams>.stride == 256)
        assert(MemoryLayout<Particle>.stride % 16 == 0)
    }
    
    func checkCollectionCompletion() {
        guard case .collecting = stateMachine.state else { return }
        
        let counterPtr = collectedCounterBuffer.contents().assumingMemoryBound(to: UInt32.self)
        let collectedCount = Int(counterPtr.pointee)
        let completionRatio = Float(collectedCount) / Float(particleCount)
        
        stateMachine.updateProgress(completionRatio)
    }
}
