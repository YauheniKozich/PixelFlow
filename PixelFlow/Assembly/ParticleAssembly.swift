//
//  ParticleAssembly.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

#if os(iOS)
import UIKit
typealias PlatformViewController = UIViewController
typealias PlatformSceneDelegate = UIResponder & UIWindowSceneDelegate
#elseif os(macOS)
import Cocoa
typealias PlatformViewController = NSViewController
typealias PlatformSceneDelegate = NSObject & NSApplicationDelegate
#endif

class ParticleAssembly {
    // MARK: - Public Methods

    /// Ассамблирует контроллер с переданным DI-контейнером
    static func assemble(withDI container: DIContainer) -> PlatformViewController {
        // Безопасное извлечение зависимостей
        guard let logger = container.resolve(LoggerProtocol.self),
              let imageLoader = container.resolve(ImageLoaderProtocol.self) else {
            fatalError("ParticleAssembly: Dependencies not registered yet in provided container")
        }

        let viewModel = ParticleViewModel(logger: logger, imageLoader: imageLoader)

        #if os(iOS)
        let viewController = ViewController(viewModel: viewModel)
        #elseif os(macOS)
        let viewController = MacViewController(viewModel: viewModel)
        #endif

        return viewController
    }

    static func makeSceneDelegate() -> PlatformSceneDelegate {
        #if os(iOS)
        return SceneDelegate()
        #elseif os(macOS)
        return MacSceneDelegate()
        #endif
    }
}
