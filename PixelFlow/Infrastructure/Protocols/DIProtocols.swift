//
//  DIProtocols.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Протоколы для Dependency Injection компонентов
//

import Foundation

/// Протокол для контейнера зависимостей
protocol DIContainerProtocol {
    /// Регистрирует сервис в контейнере
    func register<T>(_ service: T, for type: T.Type, name: String?)

    /// Разрешает зависимость из контейнера
    func resolve<T>(_ type: T.Type, name: String?) -> T?

    /// Проверяет зарегистрирована ли зависимость
    func isRegistered<T>(_ type: T.Type, name: String?) -> Bool
}