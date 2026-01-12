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
            let pass = view.currentRenderPassDescriptor,
            let commandBuffer = commandQueue.makeCommandBuffer()
        else { return }

        clock.update()
        updateSimulationParams()

        encodeCompute(into: commandBuffer)
        encodeRender(into: commandBuffer, pass: pass)

        // Проверяем завершение сбора после того, как GPU обновил счетчик
        checkCollectionCompletion()

        if case .collected = stateMachine.state {
            stateMachine.tickCollected()
        }

        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
}
