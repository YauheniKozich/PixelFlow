//
//  ParticleSystemDependencies.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Регистрация зависимостей для системы частиц
//

import Metal

/// Регистрация зависимостей для системы частиц
final class ParticleSystemDependencies {

    /// Регистрирует все зависимости для системы частиц
    static func register(in container: DIContainer) {
        Logger.shared.info("Registering ParticleSystem dependencies")

        // Metal компоненты
        registerMetalComponents(in: container)

        // Компоненты симуляции
        registerSimulationComponents(in: container)

        // Компоненты хранения
        registerStorageComponents(in: container)

        // Сервисы
        registerServices(in: container)
    }

    // MARK: - Private Registration Methods

    private static func registerMetalComponents(in container: DIContainer) {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not available")
        }

        container.register(device as MTLDevice, for: MTLDevice.self)
        container.register(device.makeCommandQueue()! as MTLCommandQueue, for: MTLCommandQueue.self)

        container.register(MetalRenderer(device: device), for: MetalRendererProtocol.self)
    }

    private static func registerSimulationComponents(in container: DIContainer) {
        container.register(DefaultStateManager(), for: ParticleSystemStateManagerProtocol.self)
        container.register(DefaultSimulationClock(), for: SimulationClockProtocol.self)
        let simulationEngine = SimulationEngine()
        Logger.shared.info("SimulationEngine created once in DI")
        container.register(simulationEngine, for: SimulationEngineProtocol.self)
        container.register(simulationEngine, for: PhysicsEngineProtocol.self)
        Logger.shared.info("Same SimulationEngine registered for both protocols")
    }

    private static func registerStorageComponents(in container: DIContainer) {
        guard let device = resolve(MTLDevice.self) else {
            fatalError("MTLDevice not registered")
        }

        container.register(ParticleStorage(device: device), for: ParticleStorageProtocol.self)
    }

    private static func registerServices(in container: DIContainer) {
        container.register(ConfigurationManager(), for: ConfigurationManagerProtocol.self)
        container.register(MemoryManager(), for: MemoryManagerProtocol.self)
        container.register(ImageParticleGeneratorToParticleSystemAdapter.makeAdapter(), for: ParticleGeneratorProtocol.self)
        container.register(Logger.shared as LoggerProtocol, for: LoggerProtocol.self)
    }
}