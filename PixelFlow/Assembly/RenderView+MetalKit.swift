//
//  RenderView+MetalKit.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 05.02.26.
//

#if os(iOS)
import UIKit
import MetalKit

extension MTKView: RenderView {}
#elseif os(macOS)
import Cocoa
import MetalKit

extension MTKView: RenderView {}
#endif
