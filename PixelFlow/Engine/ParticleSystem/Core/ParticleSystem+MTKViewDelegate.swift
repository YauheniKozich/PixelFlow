//
//  ParticleSystem+MTKViewDelegate.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit

//MARK: -Файл MTKViewDelegate.swift

extension ParticleSystem: MTKViewDelegate {
    @objc func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        // screenSize is now only in MetalRenderer
        renderer.mtkView(view, drawableSizeWillChange: size)

        if !stateMachine.isActive {
            particleGenerator.recreateParticles(in: particleBuffer, screenSize: size)
        }
    }
    
    func draw(in view: MTKView) {
        guard stateMachine.isActive else {
            return
        }

        guard view.currentDrawable != nil else {
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer() else {
            return
        }

        simulationClock.update()
        updateSimulationParams()

        guard let pass = view.currentRenderPassDescriptor else {
            return
        }

        encodeCompute(into: commandBuffer)
        encodeRender(into: commandBuffer, pass: pass)

        checkCollectionCompletion()

        if case .collected = stateMachine.state {
            stateMachine.tickCollected()
        }

        commandBuffer.present(view.currentDrawable!)
        commandBuffer.commit()
    }
}
