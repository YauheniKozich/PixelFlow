//
//  Sample.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 13.01.26.
//

import simd

struct Sample {
    let x: Int
    let y: Int
    let color: SIMD4<Float>
    
    init(x: Int, y: Int, color: SIMD4<Float>) {
        self.x = x
        self.y = y
        self.color = color
    }
}
