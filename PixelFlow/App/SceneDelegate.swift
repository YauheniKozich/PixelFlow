//
//  SceneDelegate.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 24.10.25.
//

import UIKit

@MainActor
protocol ParticleSystemLifecycleHandling: AnyObject {
    func handleWillResignActive()
    func handleDidBecomeActive()
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // MARK: - Properties
    var window: UIWindow?
    private var compositionRoot: AppCompositionRoot?

    // MARK: - UISceneDelegate

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        
        guard let windowScene = scene as? UIWindowScene else { return }
        
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        guard let appDelegate = UIApplication.shared.delegate as? AppDelegate else { return }
        let compositionRoot = appDelegate.compositionRoot
        self.compositionRoot = compositionRoot
        let rootVC = compositionRoot.makeParticleViewController()

        window.rootViewController = rootVC
        window.makeKeyAndVisible()

        compositionRoot.logger.info("SceneDelegate: окно создано и зависимости инициализированы")
    }
    
    // MARK: - Life‑cycle callbacks

    func sceneDidDisconnect(_ scene: UIScene) {
        compositionRoot?.logger.info("SceneDelegate: сцена отключена")
        window = nil
        compositionRoot = nil
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        compositionRoot?.logger.info("SceneDelegate: сцена стала активной")
        (window?.rootViewController as? ParticleSystemLifecycleHandling)?
            .handleDidBecomeActive()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        compositionRoot?.logger.info("SceneDelegate: сцена будет неактивна")
        (window?.rootViewController as? ParticleSystemLifecycleHandling)?
            .handleWillResignActive()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        compositionRoot?.logger.info("SceneDelegate: сцена переходит на передний план")
        // Можно обновить UI/данные, если это требуется.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        compositionRoot?.logger.info("SceneDelegate: сцена перешла в фон")
        if let rootVC = window?.rootViewController as? ParticleSystemLifecycleHandling {
            rootVC.handleWillResignActive()
        }
    }

    // MARK: - URL handling

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        compositionRoot?.logger.info("SceneDelegate: открытие URL контекстов")
        // Обработка deeplink‑ов, если приложение их поддерживает.
    }
}
