//
//  ImageAnalysis.swift
//  PixelFlow
//
//  СТРУКТУРЫ ДАННЫХ И АНАЛИЗ ИЗОБРАЖЕНИЙ
//  для генерации частиц
//

import CoreGraphics
import CoreImage
import simd

// MARK: - Data Structures

struct ImageAnalysis: Codable {
    let width: Int
    let height: Int
    let averageColor: SIMD3<Float>
    let contrast: Float           // RMS контраст (0-1)
    let brightness: Float
    let pixelDensity: Float
    let complexity: Int           // 0-10
    let dominantColors: [SIMD3<Float>]
    let colorVariance: Float      // Дисперсия цветов
    let edgeDensity: Float        // Плотность краев (0-1)
    let saturation: Float         // Средняя насыщенность (0-1)
}

// MARK: - Image Analysis
