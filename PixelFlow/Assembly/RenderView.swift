//
//  RenderView.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 05.02.26.
//

import CoreGraphics

/// Абстракция над render view, чтобы ViewModel не зависел от UIKit/MetalKit.
protocol RenderView: AnyObject {
    var frame: CGRect { get set }
    var bounds: CGRect { get }
    var isUserInteractionEnabled: Bool { get set }
    func setNeedsDisplay()
}
