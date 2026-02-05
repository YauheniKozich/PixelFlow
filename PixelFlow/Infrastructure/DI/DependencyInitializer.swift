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

    private static var isCoreInitialized = false
    private static var isViewInitialized = false
    private static let lock = NSLock()

    /// Инициализирует зависимости, не зависящие от конкретного MTKView
    /// Thread-safe и идемпотентный метод
    @MainActor static func initializeCore() {
        lock.lock()
        defer { lock.unlock() }

        guard !isCoreInitialized else {
            // Logger может быть еще не зарегистрирован, используем прямой доступ
            Logger.shared.debug("Core dependencies already initialized")
            return
        }

        // Регистрация Logger первым
        registerLogger(in: AppContainer.shared)

        guard let logger = AppContainer.shared.resolve(LoggerProtocol.self) else {
            // ErrorHandler еще не зарегистрирован, используем прямой доступ к логгеру
            Logger.shared.error("Critical: Failed to resolve logger after registration")
            fatalError("Failed to resolve logger after registration")
        }

        logger.info("Initializing core application dependencies...")

        // Регистрация зависимостей в правильном порядке
        AssemblyDependencies.register(in: AppContainer.shared)
        syncSharedServicesToEngineContainer()
        ImageGeneratorDependencies.register(in: EngineContainer.shared)
        ParticleSystemDependencies.registerCore(in: EngineContainer.shared)

        isCoreInitialized = true
        logger.info("Core dependencies initialized successfully")
    }

    /// Инициализирует зависимости, зависящие от MTKView (размер, storage, simulation)
    /// Thread-safe и идемпотентный метод
    @MainActor static func configureForView(metalView: MTKView) {
        lock.lock()
        let needsCoreInit = !isCoreInitialized
        let needsViewInit = !isViewInitialized
        lock.unlock()

        if needsCoreInit {
            initializeCore()
        }

        guard needsViewInit else {
            Logger.shared.debug("View-dependent dependencies already initialized")
            return
        }

        lock.lock()
        defer { lock.unlock() }

        guard !isViewInitialized else { return }

        guard let logger = AppContainer.shared.resolve(LoggerProtocol.self) else {
            Logger.shared.error("Critical: Failed to resolve logger before view-dependent init")
            fatalError("Failed to resolve logger before view-dependent init")
        }

        logger.info("Initializing view-dependent dependencies...")
        ParticleSystemDependencies.registerViewDependent(in: EngineContainer.shared, metalView: metalView)

        isViewInitialized = true
        logger.info("View-dependent dependencies initialized successfully")
    }

    private static func registerLogger(in container: DIContainer) {
        container.register(Logger.shared as LoggerProtocol, for: LoggerProtocol.self)
    }

    private static func syncSharedServicesToEngineContainer() {
        // Прокидываем общие сервисы из AppContainer в EngineContainer
        if let logger = AppContainer.shared.resolve(LoggerProtocol.self) {
            EngineContainer.shared.register(logger, for: LoggerProtocol.self)
        }
        if let errorHandler = AppContainer.shared.resolve(ErrorHandlerProtocol.self) {
            EngineContainer.shared.register(errorHandler, for: ErrorHandlerProtocol.self)
        }
        if let memoryManager = AppContainer.shared.resolve(MemoryManagerProtocol.self) {
            EngineContainer.shared.register(memoryManager, for: MemoryManagerProtocol.self)
        }
    }

    /// Проверяет, были ли инициализированы зависимости
    static var isDependenciesInitialized: Bool {
        lock.lock()
        defer { lock.unlock() }
        return isCoreInitialized && isViewInitialized
    }

    /// Сбрасывает состояние инициализации (для тестирования)
    static func reset() {
        lock.lock()
        defer { lock.unlock() }

        isCoreInitialized = false
        isViewInitialized = false
        AppContainer.shared.reset()
        EngineContainer.shared.reset()
        // Logger может быть сброшен, используем прямой доступ
        Logger.shared.info("Dependencies reset")
    }
}
