//
//  AssemblyDependencies.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Регистрация зависимостей для Assembly слоя
//

import Foundation

/// Регистрация зависимостей для Assembly слоя
final class AssemblyDependencies {
    
    /// Регистрирует все зависимости для Assembly
    static func register(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        logger.info("Registering Assembly dependencies")
        
        // Сервисы Assembly
        registerServices(in: container, logger: logger)
    }
    
    // MARK: - Private Registration Methods
    
    private static func registerServices(in container: DIContainer, logger: LoggerProtocol) {
        // ImageLoader
        container.register(ImageLoader(logger: logger), for: ImageLoaderProtocol.self)
        
        // ErrorHandler - централизованная обработка ошибок
        let errorHandler = ErrorHandler(logger: logger)
        container.register(errorHandler, for: ErrorHandlerProtocol.self)
    }
}
