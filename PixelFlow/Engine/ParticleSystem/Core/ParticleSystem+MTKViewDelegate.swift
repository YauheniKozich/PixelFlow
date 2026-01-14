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
        screenSize = size
        imageController.updateScreenSize(size)
        
        if !stateMachine.isActive {
            particleGenerator.recreateParticles(in: particleBuffer)
        }
    }
    
    func draw(in view: MTKView) {
        guard
            stateMachine.isActive,
            let drawable = view.currentDrawable,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        clock.update()
        updateSimulationParams()
        
        let pass = MTLRenderPassDescriptor()
        pass.colorAttachments[0].texture = drawable.texture
        pass.colorAttachments[0].loadAction = .clear
        pass.colorAttachments[0].storeAction = .store
        pass.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        
        encodeCompute(into: commandBuffer)
        encodeRender(into: commandBuffer, pass: pass)

        checkCollectionCompletion()

        if case .collected = stateMachine.state {
            stateMachine.tickCollected()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
