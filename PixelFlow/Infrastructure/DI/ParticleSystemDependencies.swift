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
@MainActor
final class ParticleSystemDependencies {
    
    /// Регистрирует зависимости, не зависящие от размера или конкретного MTKView
    static func registerCore(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        logger.info("Registering ParticleSystem core dependencies")
        
        // Сервисы
        registerServices(in: container)
        
        // Metal компоненты
        registerMetalComponents(in: container)
    }
    
    /// Регистрирует зависимости, зависящие от конкретного MTKView (размер, storage, simulation)
    static func registerViewDependent(in container: DIContainer, metalView: MTKView) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        logger.info("Registering ParticleSystem view-dependent dependencies")
        
        // Компоненты хранения
        let drawableSize = metalView.drawableSize
        let fallbackSize = metalView.bounds.size
        let viewSize = (drawableSize.width > 0 && drawableSize.height > 0) ? drawableSize : fallbackSize
        registerStorageComponents(in: container, viewSize: viewSize)
        
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
        
        do {
            let metalRenderer = try MetalRenderer(device: device, logger: logger)
            container.register(metalRenderer, for: MetalRendererProtocol.self)
        } catch {
            fatalError("Failed to create MetalRenderer: \(error)")
        }
    }
    
    private static func registerSimulationComponents(in container: DIContainer) {
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
    
    private static func registerServices(in container: DIContainer) {
        guard let logger = container.resolve(LoggerProtocol.self) else {
            fatalError("Logger not registered")
        }
        container.register(ConfigurationManager(logger: logger), for: ConfigurationManagerProtocol.self)
    }
}
