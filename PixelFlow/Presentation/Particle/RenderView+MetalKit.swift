//
//  RenderView+MetalKit.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 05.02.26.
//
//  NOTE: Используем marker protocol для избегания retroactive conformance.
//  Прямое extension MTKView: RenderView может конфликрировать с будущими SDK.

#if os(iOS)
import UIKit
import MetalKit

/// Marker protocol для безопасной retroactive conformance MTKView → RenderView
protocol MetalRenderView: RenderView {}
extension MTKView: MetalRenderView {}
#elseif os(macOS)
import Cocoa
import MetalKit

/// Marker protocol для безопасной retroactive conformance MTKView → RenderView
protocol MetalRenderView: RenderView {}
extension MTKView: MetalRenderView {}
#endif
