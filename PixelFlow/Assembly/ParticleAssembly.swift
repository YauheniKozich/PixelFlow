//
//  ParticleAssembly.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

#if os(iOS)
import UIKit
import MetalKit
typealias PlatformViewController = UIViewController
typealias PlatformSceneDelegate = UIResponder & UIWindowSceneDelegate
#elseif os(macOS)
import Cocoa
import MetalKit
typealias PlatformViewController = NSViewController
typealias PlatformSceneDelegate = NSObject & NSApplicationDelegate
#endif

class ParticleAssembly {
    // MARK: - Public Methods

    /// Ассамблирует контроллер с переданным DI-контейнером
    @MainActor static func assemble(withDI container: DIContainer) -> PlatformViewController {
        // Безопасное извлечение зависимостей
        guard let logger = container.resolve(LoggerProtocol.self),
              let imageLoader = container.resolve(ImageLoaderProtocol.self) else {
            fatalError("ParticleAssembly: Dependencies not registered yet in provided container")
        }

        guard let errorHandler = container.resolve(ErrorHandlerProtocol.self) else {
            fatalError("ParticleAssembly: ErrorHandler not registered")
        }

        let viewModel = ParticleViewModel(
            logger: logger,
            imageLoader: imageLoader,
            errorHandler: errorHandler,
            renderViewFactory: { frame in
                ParticleSystemFactory.makeRenderView(frame: frame)
            },
            systemFactory: { view in
                ParticleSystemFactory.makeController(for: view)
            }
        )

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

// MARK: - Private Engine Factory

@MainActor
private protocol ParticleSystemFactoryProtocol {
    static func makeRenderView(frame: CGRect) -> RenderView
    static func makeController(for view: RenderView) -> ParticleSystemControlling?
}

private enum ParticleSystemFactory: ParticleSystemFactoryProtocol {
    static func makeRenderView(frame: CGRect) -> RenderView {
        let device = resolveEngine(MTLDevice.self) ?? MTLCreateSystemDefaultDevice()
        let view = MTKView(frame: frame, device: device)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }

    static func makeController(for view: RenderView) -> ParticleSystemControlling? {
        guard let metalView = view as? MTKView else {
            return nil
        }
        DependencyInitializer.configureForView(metalView: metalView)
        guard let metalRenderer = resolveEngine(MetalRendererProtocol.self),
              let simulationEngine = resolveEngine(SimulationEngineProtocol.self),
              let storage = resolveEngine(ParticleStorageProtocol.self),
              let configManager = resolveEngine(ConfigurationManagerProtocol.self),
              let generator = resolveEngine(ParticleGeneratorProtocol.self),
              let logger = resolveEngine(LoggerProtocol.self),
              let clock = resolveEngine(SimulationClockProtocol.self) else {
            fatalError("Failed to resolve ParticleSystem dependencies")
        }
        let controller = ParticleSystemController(
            renderer: metalRenderer,
            simulationEngine: simulationEngine,
            clock: clock,
            storage: storage,
            configManager: configManager,
            generator: generator,
            logger: logger
        )
        do {
            try controller.configureView(metalView)
        } catch {
            logger.error("Failed to configure Metal view in factory: \(error)")
        }
        return controller
    }
}
