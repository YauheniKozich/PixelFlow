//
//  RenderEncoding.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit

extension ParticleSystem {
    func encodeRender(into buffer: MTLCommandBuffer, pass: MTLRenderPassDescriptor) {
        let encoder = buffer.makeRenderCommandEncoder(descriptor: pass)!
        encoder.setRenderPipelineState(renderPipeline)
        encoder.setVertexBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setVertexBuffer(paramsBuffer, offset: 0, index: 1)
        
        encoder.setFragmentBuffer(paramsBuffer, offset: 0, index: 1)
        encoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: particleCount)
        encoder.endEncoding()
    }
}
