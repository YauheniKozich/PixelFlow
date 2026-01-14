//
//  AppDelegate.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 24.10.25.
//

import UIKit

import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    // MARK: - UIApplicationDelegate
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {

        Logger.shared.info("🚀 Приложение запущено")

        configureAppearance()

        return true
    }

    // MARK: - UISceneSession Lifecycle

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {

        Logger.shared.info("Создание новой сессии сцены")
        return UISceneConfiguration(name: "Default Configuration",
                                     sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication,
                     didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {

        Logger.shared.info("Сессии сцены закрыты: \(sceneSessions.count)")
    }

    // MARK: - System notifications

    func applicationDidReceiveMemoryWarning(_ application: UIApplication) {
        Logger.shared.warning("Получено системное уведомление о низкой памяти")
        // Если нужны глобальные очистки, делайте их здесь.
    }

    func applicationWillTerminate(_ application: UIApplication) {
        Logger.shared.info("Приложение завершает работу")
        // Финальная очистка ресурсов (если есть глобальные singleton‑ы).
    }

    // MARK: - Private Helpers

    /// Оформление `UINavigationBar` для всех контроллеров приложения.
    private func configureAppearance() {
        if #available(iOS 13.0, *) {
            let appearance = UINavigationBarAppearance()
            appearance.configureWithOpaqueBackground()
            appearance.backgroundColor = .black
            appearance.titleTextAttributes = [.foregroundColor: UIColor.white]

            UINavigationBar.appearance().standardAppearance = appearance
            UINavigationBar.appearance().scrollEdgeAppearance = appearance
        } else {
            // Поддержка старых версий (не обязателен, если минимум iOS‑13).
            UINavigationBar.appearance().barTintColor = .black
            UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
        }
    }
}
