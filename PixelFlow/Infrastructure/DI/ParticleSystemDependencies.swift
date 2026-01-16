//
//  ParticleSystemDependencies.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Регистрация зависимостей для системы частиц
//

import Foundation
import Metal
import MetalKit

/// Регистрация зависимостей для системы частиц
final class ParticleSystemDependencies {

    /// Регистрирует все зависимости для системы частиц
    static func register(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        logger.info("Registering ParticleSystem dependencies")

        // Сервисы
        registerServices(in: container)

        // Metal компоненты
        registerMetalComponents(in: container)

        // Компоненты хранения
        registerStorageComponents(in: container)

        // Компоненты симуляции
        registerSimulationComponents(in: container)
    }

    // MARK: - Private Registration Methods

    private static func registerMetalComponents(in container: DIContainer) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not available")
        }

        container.register(device as MTLDevice, for: MTLDevice.self)
        container.register(device.makeCommandQueue()! as MTLCommandQueue, for: MTLCommandQueue.self)

        // Resolve logger for MetalRenderer
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }

        container.register(MetalRenderer(device: device, logger: logger), for: MetalRendererProtocol.self)
    }

    private static func registerSimulationComponents(in container: DIContainer) {
        container.register(DefaultStateManager(), for: StateManagerProtocol.self)
        container.register(DefaultSimulationClock(), for: SimulationClockProtocol.self)

        // Resolve dependencies for SimulationEngine
        guard let stateManager = container.resolve(StateManagerProtocol.self),
              let clock = container.resolve(SimulationClockProtocol.self),
              let logger = container.resolve(LoggerProtocol.self),
              let particleStorage = container.resolve(ParticleStorageProtocol.self) else {
            fatalError("Failed to resolve simulation dependencies")
        }

        let simulationEngine = SimulationEngine(stateManager: stateManager, clock: clock, logger: logger, particleStorage: particleStorage)
        logger.info("SimulationEngine created with resolved dependencies")
        container.register(simulationEngine, for: SimulationEngineProtocol.self)
        container.register(simulationEngine, for: PhysicsEngineProtocol.self)
        logger.info("Same SimulationEngine registered for both protocols")
    }

    private static func registerStorageComponents(in container: DIContainer) {
        guard let device = container.resolve(MTLDevice.self),
              let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Required dependencies not registered")
        }

        container.register(ParticleStorage(device: device, logger: logger)!, for: ParticleStorageProtocol.self)
    }

    private static func registerServices(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        container.register(ConfigurationManager(logger: logger), for: ConfigurationManagerProtocol.self)
        container.register(MemoryManager(), for: MemoryManagerProtocol.self)
    }
}
