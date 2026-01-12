//
//  SceneDelegate.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 24.10.25.
//

import UIKit

class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?

    
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = (scene as? UIWindowScene) else { return }
        
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = ParticleAssembly.assemble() 
        self.window = window
        window.makeKeyAndVisible()
    }
    
    func sceneDidDisconnect(_ scene: UIScene) {
        // Вызывается, когда сцена освобождается системой.
        // Это происходит вскоре после того, как сцена переходит в фоновый режим, или когда ее сессия закрывается.
        // Освободите любые ресурсы, связанные с этой сценой, которые могут быть воссозданы при следующем подключении сцены.
        // Сцена может переподключиться позже, поскольку ее сессия не обязательно была закрыта (см. `application:didDiscardSceneSessions` вместо этого).
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        // Вызывается, когда сцена перешла из неактивного состояния в активное.
        // Используйте этот метод для перезапуска задач, которые были приостановлены (или еще не начаты), когда сцена была неактивной.
    }

    func sceneWillResignActive(_ scene: UIScene) {
        // Вызывается, когда сцена перейдет из активного состояния в неактивное.
        // Это может произойти из-за временных прерываний (например, входящий телефонный звонок).
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        // Вызывается при переходе сцены из фона на передний план.
        // Используйте этот метод для отмены изменений, сделанных при переходе в фон.
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        // Вызывается при переходе сцены с переднего плана в фон.
        // Используйте этот метод для сохранения данных, освобождения общих ресурсов и хранения достаточной информации о состоянии сцены
        // для восстановления сцены в ее текущее состояние.
    }


}

