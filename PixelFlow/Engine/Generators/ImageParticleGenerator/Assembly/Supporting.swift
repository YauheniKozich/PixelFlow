//
//  Supporting.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 14.01.26.
//

import Foundation

// MARK: - Supporting Structures

struct TransformationParams {
    let scaleX: CGFloat
    let scaleY: CGFloat
    let offset: CGPoint
    let mode: ImageDisplayMode
}

enum ImageDisplayMode: String, CaseIterable {
    case fit, fill, stretch, center
    
    var description: String {
        switch self {
        case .fit: return "Fit (сохранить пропорции)"
        case .fill: return "Fill (заполнить экран)"
        case .stretch: return "Stretch (растянуть)"
        case .center: return "Center (центрировать)"
        }
    }
}
