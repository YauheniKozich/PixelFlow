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

    /// Размер экрана для позиционирования (по умолчанию)
    var screenSize: CGSize { get set }

    /// Генерирует частицы из изображения
    func generateParticles() throws -> [Particle]

    /// Генерирует частицы с указанным размером экрана
    func generateParticles(screenSize: CGSize) throws -> [Particle]

    /// Обновляет размер экрана
    func updateScreenSize(_ size: CGSize)
}