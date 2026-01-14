//
//  SceneDelegate.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 24.10.25.
//

import UIKit

import UIKit

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    // MARK: - Properties
    var window: UIWindow?
    private var viewModel: ParticleViewModel?

    // MARK: - UISceneDelegate

    func scene(_ scene: UIScene,
               willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {

        guard let windowScene = scene as? UIWindowScene else { return }

        Logger.shared.info("SceneDelegate: сцена подключается")
        
        viewModel = ParticleViewModel()
        viewModel?.setHighQualityConfiguration()          // ← один‑единственный метод конфигурации

        let window = UIWindow(windowScene: windowScene)

        guard viewModel != nil else {
            assertionFailure("ViewModel не создаётся")
            return
        }

        let rootVC = ParticleAssembly.assemble()

        window.rootViewController = rootVC
        window.makeKeyAndVisible()
        self.window = window

        Logger.shared.info("SceneDelegate настроен, окно создано")
    }

    // MARK: - Life‑cycle callbacks

    func sceneDidDisconnect(_ scene: UIScene) {
        Logger.shared.info("SceneDelegate: сцена отключена")
        // Важно освободить ресурсы, когда пользователь закрывает окно.
        viewModel?.cleanupAllResources()
        viewModel = nil
        window = nil
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Logger.shared.info("SceneDelegate: сцена стала активной")
        resumeParticleSimulation()
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Logger.shared.info("SceneDelegate: сцена будет неактивна")
        pauseParticleSimulation()
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Logger.shared.info("SceneDelegate: сцена переходит на передний план")
        // Можно обновить UI/данные, если это требуется.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Logger.shared.info("SceneDelegate: сцена перешла в фон")
        viewModel?.cleanupAllResources()
    }

    // MARK: - URL handling

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        Logger.shared.info("SceneDelegate: открытие URL контекстов")
        // Обработка deeplink‑ов, если приложение их поддерживает.
    }

    // MARK: - Private helpers

    private func pauseParticleSimulation() {
        viewModel?.particleSystem?.stop()
    }

    private func resumeParticleSimulation() {
        viewModel?.particleSystem?.startSimulation()
    }
}
