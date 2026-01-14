//
//  DIContainer.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Dependency Injection Container для управления зависимостями
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

/// Реализация контейнера зависимостей
final class DIContainer: DIContainerProtocol {
    private var services = [ServiceKey: Any]()
    private let lock = NSLock()

    private struct ServiceKey: Hashable {
        let type: Any.Type
        let name: String?

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(type))
            hasher.combine(name)
        }

        static func == (lhs: ServiceKey, rhs: ServiceKey) -> Bool {
            return lhs.type == rhs.type && lhs.name == rhs.name
        }
    }

    func register<T>(_ service: T, for type: T.Type = T.self, name: String? = nil) {
        lock.lock()
        defer { lock.unlock() }

        let key = ServiceKey(type: type, name: name)
        services[key] = service
    }

    func resolve<T>(_ type: T.Type = T.self, name: String? = nil) -> T? {
        lock.lock()
        defer { lock.unlock() }

        let key = ServiceKey(type: type, name: name)
        return services[key] as? T
    }

    func isRegistered<T>(_ type: T.Type = T.self, name: String? = nil) -> Bool {
        lock.lock()
        defer { lock.unlock() }

        let key = ServiceKey(type: type, name: name)
        return services[key] != nil
    }

    /// Очищает все зарегистрированные сервисы
    func reset() {
        lock.lock()
        defer { lock.unlock() }

        services.removeAll()
    }
}

/// Thread-safe singleton для главного контейнера приложения
final class AppContainer {
    static let shared = DIContainer()

    private init() {}
}

/// Удобный глобальный доступ к контейнеру
func resolve<T>(_ type: T.Type = T.self, name: String? = nil) -> T? {
    return AppContainer.shared.resolve(type, name: name)
}

func register<T>(_ service: T, for type: T.Type = T.self, name: String? = nil) {
    AppContainer.shared.register(service, for: type, name: name)
}

func isRegistered<T>(_ type: T.Type = T.self, name: String? = nil) -> Bool {
    return AppContainer.shared.isRegistered(type, name: name)
}