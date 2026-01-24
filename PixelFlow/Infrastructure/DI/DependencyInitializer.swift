//
//  DependencyInitializer.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Централизованный инициализатор всех зависимостей приложения
//

import Foundation
import MetalKit

/// Централизованный инициализатор зависимостей
/// Гарантирует однократную регистрацию всех зависимостей приложения
final class DependencyInitializer {

    private static var isInitialized = false
    private static let lock = NSLock()

    /// Инициализирует все зависимости приложения
    /// Thread-safe и идемпотентный метод
    @MainActor static func initialize(metalView: MTKView) {
        lock.lock()
        defer { lock.unlock() }

        guard !isInitialized else {
            // Logger может быть еще не зарегистрирован, используем прямой доступ
            Logger.shared.debug("Dependencies already initialized")
            return
        }

        // Регистрация Logger первым
        registerLogger(in: AppContainer.shared)

        guard let logger = AppContainer.shared.resolve(LoggerProtocol.self) else {
            // ErrorHandler еще не зарегистрирован, используем прямой доступ к логгеру
            Logger.shared.error("Critical: Failed to resolve logger after registration")
            fatalError("Failed to resolve logger after registration")
        }

        logger.info("Initializing application dependencies...")

        // Регистрация зависимостей в правильном порядке
        AssemblyDependencies.register(in: AppContainer.shared)
        ImageGeneratorDependencies.register(in: AppContainer.shared)
        ParticleSystemDependencies.register(in: AppContainer.shared, metalView: metalView)

        isInitialized = true
        logger.info("All dependencies initialized successfully")
    }

    private static func registerLogger(in container: DIContainer) {
        container.register(Logger.shared as LoggerProtocol, for: LoggerProtocol.self)
    }

    /// Проверяет, были ли инициализированы зависимости
    static var isDependenciesInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isInitialized
    }

    /// Сбрасывает состояние инициализации (для тестирования)
    static func reset() {
        lock.lock()
        defer { lock.unlock() }

        isInitialized = false
        AppContainer.shared.reset()
        // Logger может быть сброшен, используем прямой доступ
        Logger.shared.info("Dependencies reset")
    }
}
