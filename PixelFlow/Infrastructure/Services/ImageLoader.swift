//
//  ImageLoader.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Сервис для загрузки изображений
//

import UIKit
import CoreGraphics

/// Сервис для загрузки изображений
final class ImageLoader: ImageLoaderProtocol {

    // MARK: - Properties

    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(logger: LoggerProtocol = Logger.shared) {
        self.logger = logger
    }

    // MARK: - ImageLoaderProtocol

    func loadImage(named name: String) -> CGImage? {
        if let uiImage = UIImage(named: name) {
            logger.info("Loaded bundled image '\(name)' – \(uiImage.size.width)x\(uiImage.size.height) pts")
            return uiImage.cgImage
        }
        return nil
    }

    func loadImage(from url: URL) async throws -> CGImage {
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let uiImage = UIImage(data: data),
              let cgImage = uiImage.cgImage else {
            throw ImageLoaderError.invalidImageData
        }

        logger.info("Loaded image from URL: \(url.lastPathComponent) – \(uiImage.size.width)x\(uiImage.size.height) pts")
        return cgImage
    }

    func createTestImage() -> CGImage? {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)

        let uiImage = renderer.image { ctx in
            // Gradient background
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.systemBlue.cgColor,
                         UIColor.systemPurple.cgColor] as CFArray,
                locations: [0, 1]) {

                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }

            // White outer circle
            UIColor.white.setFill()
            UIBezierPath(
                ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 100, dy: 100)
            ).fill()

            // Black inner circle
            UIColor.black.setFill()
            UIBezierPath(
                ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 200, dy: 200)
            ).fill()
        }

        return uiImage.cgImage
    }

    // MARK: - Public Methods

    /// Загружает изображение с fallback к тестовому изображению
    func loadImageWithFallback() -> CGImage? {
        let possibleNames = ["steve", "test", "image"]

        for name in possibleNames {
            if let image = loadImage(named: name) {
                return image
            }
        }

        logger.info("No bundled image found – generating test pattern")
        return createTestImage()
    }
}

