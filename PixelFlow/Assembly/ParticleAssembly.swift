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

    static func assemble() -> PlatformViewController {
        let viewModel = ParticleViewModel()

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
