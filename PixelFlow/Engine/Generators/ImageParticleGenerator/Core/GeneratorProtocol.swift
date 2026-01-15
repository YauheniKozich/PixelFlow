//
//  GeneratorProtocol.swift
//  PixelFlow
//
//  Протокол для генераторов частиц
//

import CoreGraphics

/// Протокол для генераторов частиц из изображений
protocol ImageParticleGeneratorProtocol {
    /// Исходное изображение
    var image: CGImage { get }





    /// Генерирует частицы с указанным размером экрана
    func generateParticles(screenSize: CGSize) throws -> [Particle]


    
    /// Очистка кэша
    func clearCache()
}

protocol Cleanable: AnyObject {
    func cleanup()
}
