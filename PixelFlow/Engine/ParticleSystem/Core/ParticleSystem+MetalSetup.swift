//
//  ParticleSystem+MetalSetup.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit


extension ParticleSystem {
    // MARK: - Metal Setup
    
    func configureView(_ view: MTKView) {
        view.device = device
        view.delegate = self
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = false
        view.preferredFramesPerSecond = 60

        // Включаем сглаживание для устранения пиксельной сетки
        view.sampleCount = 4  // MSAA 4x для сглаживания

        // Disable automatic rendering - use CADisplayLink instead
        view.isPaused = true
        view.enableSetNeedsDisplay = false
    }
    
    func setupPipelines(view: MTKView) throws {
        let library = device.makeDefaultLibrary()!
        
        computePipeline = try device.makeComputePipelineState(
            function: library.makeFunction(name: "updateParticles")!
        )
        
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = library.makeFunction(name: "vertexParticle")
        desc.fragmentFunction = library.makeFunction(name: "fragmentParticle")
        desc.colorAttachments[0].pixelFormat = view.colorPixelFormat
        desc.sampleCount = view.sampleCount  // Синхронизируем sampleCount с view
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].rgbBlendOperation = .add
        desc.colorAttachments[0].alphaBlendOperation = .add
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
//        
        let ca = desc.colorAttachments[0]!
        ca.isBlendingEnabled = true
        ca.sourceRGBBlendFactor = .sourceAlpha
        ca.destinationRGBBlendFactor = .oneMinusSourceAlpha
        
        renderPipeline = try device.makeRenderPipelineState(descriptor: desc)
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
        // Set back-reference for idle chaotic motion
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
        // Only check progress in collecting state
        guard case .collecting = stateMachine.state else { return }
        
        let counterPtr = collectedCounterBuffer.contents().assumingMemoryBound(to: UInt32.self)
        let collectedCount = Int(counterPtr.pointee)
        let completionRatio = Float(collectedCount) / Float(particleCount)
        
        // Обновляем прогресс в state machine
        stateMachine.updateProgress(completionRatio)
        
        let currentTime = CACurrentMediaTime()
        
        // Логируем прогресс раз в секунду или если изменился collectedCount
        if collectedCount != lastLoggedCollectedCount && currentTime - lastProgressLogTime > 1.0 {
            Logger.shared.info("Collection progress: \(collectedCount)/\(particleCount) (\(String(format: "%.1f", completionRatio * 100))%)")
            lastProgressLogTime = currentTime
            lastLoggedCollectedCount = collectedCount
        }
        
        // Логика завершения теперь в stateMachine.updateProgress()
        if case .collected = stateMachine.state {
            Logger.shared.info("✅ Collection complete! State is now .collected")
            // Don't auto-stop - let user control when to stop
        }
    }
}
