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
    @MainActor static func register(in container: DIContainer, metalView: MTKView) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        logger.info("Registering ParticleSystem dependencies")
        
        // Сервисы
        registerServices(in: container)
        
        // Metal компоненты
        registerMetalComponents(in: container)
        
        // Компоненты хранения
        registerStorageComponents(in: container, viewSize: metalView.bounds.size)
        
        // Компоненты симуляции
        registerSimulationComponents(in: container)
    }
    
    // MARK: - Private Registration Methods
    
    @MainActor private static func registerMetalComponents(in container: DIContainer) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not available")
        }
        
        container.register(device as MTLDevice, for: MTLDevice.self)
        container.register(device.makeCommandQueue()! as MTLCommandQueue, for: MTLCommandQueue.self)
        
        // Resolve logger for MetalRenderer
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        
        do {
            let metalRenderer = try MetalRenderer(device: device, logger: logger)
            container.register(metalRenderer, for: MetalRendererProtocol.self)
        } catch {
            fatalError("Failed to create MetalRenderer: \(error)")
        }
    }
    
    @MainActor private static func registerSimulationComponents(in container: DIContainer) {
        let stateManager = SimulationStateMachine()
        container.register(stateManager, for: SimulationStateMachine.self)
        container.register(DefaultSimulationClock(), for: SimulationClockProtocol.self)
        
        // Resolve dependencies for SimulationEngine
        guard let clock = container.resolve(SimulationClockProtocol.self),
              let logger = container.resolve(LoggerProtocol.self),
              let particleStorage = container.resolve(ParticleStorageProtocol.self) else {
            fatalError("Failed to resolve simulation dependencies")
        }
        
        let simulationEngine = SimulationEngine(stateManager: stateManager, clock: clock, logger: logger, particleStorage: particleStorage)
        logger.info("SimulationEngine created with resolved dependencies")
        container.register(simulationEngine, for: SimulationEngineProtocol.self)
        //  container.register(simulationEngine, for: PhysicsEngineProtocol.self)
        logger.info("Same SimulationEngine registered for both protocols")
    }
    
    private static func registerStorageComponents(in container: DIContainer, viewSize: CGSize) {
        guard let device = container.resolve(MTLDevice.self),
              let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Required dependencies not registered")
        }
        guard let particleStorage = ParticleStorage(device: device, logger: logger, viewSize: viewSize) else {
            fatalError("Failed to create ParticleStorage")
        }
        container.register(particleStorage, for: ParticleStorageProtocol.self)
    }
    
    @MainActor private static func registerServices(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        container.register(ConfigurationManager(logger: logger), for: ConfigurationManagerProtocol.self)
        container.register(MemoryManager(), for: MemoryManagerProtocol.self)
    }
}
