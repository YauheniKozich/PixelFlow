//
//  ComputeEncoding.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import MetalKit

extension ParticleSystem {
    func encodeCompute(into buffer: MTLCommandBuffer) {
        let encoder = buffer.makeComputeCommandEncoder()!
        encoder.setComputePipelineState(computePipeline)
        encoder.setBuffer(particleBuffer, offset: 0, index: 0)
        encoder.setBuffer(paramsBuffer, offset: 0, index: 1)
        encoder.setBuffer(collectedCounterBuffer, offset: 0, index: 2)
        
        let w = computePipeline.threadExecutionWidth
        encoder.dispatchThreadgroups(
            MTLSize(width: (particleCount + w - 1) / w, height: 1, depth: 1),
            threadsPerThreadgroup: MTLSize(width: w, height: 1, depth: 1)
        )
        encoder.endEncoding()
    }
}
