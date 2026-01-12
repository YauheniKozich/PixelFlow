//
//  AppDelegate.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 24.10.25.
//

import UIKit

@main
class AppDelegate: UIResponder, UIApplicationDelegate {



    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        // Точка переопределения для настройки после запуска приложения.
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(_ application: UIApplication, configurationForConnecting connectingSceneSession: UISceneSession, options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        // Вызывается при создании новой сессии сцены.
        // Используйте этот метод для выбора конфигурации для создания новой сцены.
        return UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication, didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        // Вызывается, когда пользователь закрывает сессию сцены.
        // Если какие-либо сессии были закрыты, пока приложение не работало, это будет вызвано вскоре после application:didFinishLaunchingWithOptions.
        // Используйте этот метод для освобождения ресурсов, специфичных для закрытых сцен, так как они не вернутся.
    }


}

