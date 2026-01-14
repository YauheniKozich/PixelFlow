//
//  Protocol.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 14.01.26.
//

import Foundation

protocol ParticleGeneratorConfigurationWithDisplayMode: ParticleGeneratorConfiguration {
    var imageDisplayMode: ImageDisplayMode { get }
    var particleLifetime: Float { get }
    var particleSpeed: Float { get }
    var particleSizeUltra: ClosedRange<Float>? { get }
    var particleSizeHigh: ClosedRange<Float>? { get }
    var particleSizeStandard: ClosedRange<Float>? { get }
    var particleSizeLow: ClosedRange<Float>? { get }
}
