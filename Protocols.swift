//
//  Protocols.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import CoreGraphics
import Foundation
import simd

// MARK: - Data Structures

/// Структура для хранения сэмпла пикселя
struct Sample { // но возможно его стоит сделать Codable
    let x: Int
    let y: Int
    let color: SIMD4<Float>
    
//    // MARK: - Coding Keys
//    private enum CodingKeys: String, CodingKey {
//        case x
//        case y
//        case color   // будет сохраняться как массив [r,g,b,a]
//    }
//    
//    // MARK: - Encoder
//    func encode(to encoder: Encoder) throws {
//        var container = encoder.container(keyedBy: CodingKeys.self)
//        
//        try container.encode(x, forKey: .x)
//        try container.encode(y, forKey: .y)
//        
//        // SIMD4<Float> → массив из 4 Float
//        let rgbaArray: [Float] = [color.x, color.y, color.z, color.w]
//        try container.encode(rgbaArray, forKey: .color)
//    }
//    
//    // MARK: - Decoder
//    init(from decoder: Decoder) throws {
//        let container = try decoder.container(keyedBy: CodingKeys.self)
//        
//        x = try container.decode(Int.self, forKey: .x)
//        y = try container.decode(Int.self, forKey: .y)
//        
//        // Декодируем массив из 4 Float и конструируем SIMD‑вектор
//        let rgbaArray = try container.decode([Float].self, forKey: .color)
//        
//        // Защищаемся от некорректных файлов (меньше‑четырёх элементов)
//        guard rgbaArray.count == 4 else {
//            throw DecodingError.dataCorruptedError(
//                forKey: .color,
//                in: container,
//                debugDescription: "Expected 4 Float values for color, got \(rgbaArray.count)."
//            )
//        }
//        
//        color = SIMD4<Float>(rgbaArray[0], rgbaArray[1], rgbaArray[2], rgbaArray[3])
//    }
}

// MARK: - Core Protocols

/// Протокол для анализа изображений
protocol ImageAnalyzer {
    func analyze(image: CGImage) throws -> ImageAnalysis
}

/// Протокол для сэмплинга пикселей
protocol PixelSampler {
    func samplePixels(from analysis: ImageAnalysis, targetCount: Int, config: ParticleGeneratorConfiguration, image: CGImage) throws -> [Sample]
}

/// Протокол для сборки частиц
protocol ParticleAssembler {
    func assembleParticles(from samples: [Sample], config: ParticleGeneratorConfiguration, screenSize: CGSize, imageSize: CGSize) -> [Particle]
}

/// Протокол для кэширования результатов
protocol CacheManager: AnyObject {
    func cache<T: Codable>(_ value: T, for key: String) throws
    func retrieve<T: Codable>(_ type: T.Type, for key: String) throws -> T?
    func clear()
}

/// Протокол для отслеживания прогресса генерации
protocol ParticleGeneratorDelegate: AnyObject {
    func generator(_ generator: ImageParticleGenerator, didUpdateProgress progress: Float, stage: String)
    func generator(_ generator: ImageParticleGenerator, didEncounterError error: Error)
    func generatorDidFinish(_ generator: ImageParticleGenerator, particles: [Particle])
}

/// Протокол для конфигурации генерации
protocol ParticleGeneratorConfiguration: Codable {
    var samplingStrategy: SamplingStrategy { get }
    var qualityPreset: QualityPreset { get }
    var enableCaching: Bool { get }
    var maxConcurrentOperations: Int { get }
}

// MARK: - Supporting Types

enum SamplingStrategy: Codable, Equatable {
    case uniform         // Равномерный сэмплинг
    case importance      // По важности пикселей
    case adaptive        // Адаптивная плотность
    case hybrid          // Комбинированный подход
    case advanced(SamplingAlgorithm)  // Продвинутые алгоритмы
}

enum QualityPreset: Codable {
    case draft     // Быстрый черновик
    case standard  // Стандартное качество
    case high      // Высокое качество
    case ultra     // Максимальное качество
}

enum GeneratorError: LocalizedError {
    case invalidImage
    case invalidParticleCount
    case analysisFailed(reason: String)
    case samplingFailed(reason: String)
    case assemblyFailed(reason: String)
    case cacheError(reason: String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
        case .invalidImage:
            return "Некорректное изображение"
        case .invalidParticleCount:
            return "Некорректное количество частиц"
        case .analysisFailed(let reason):
            return "Ошибка анализа: \(reason)"
        case .samplingFailed(let reason):
            return "Ошибка сэмплинга: \(reason)"
        case .assemblyFailed(let reason):
            return "Ошибка сборки частиц: \(reason)"
        case .cacheError(let reason):
            return "Ошибка кэша: \(reason)"
        case .cancelled:
            return "Операция отменена"
        }
    }
}
