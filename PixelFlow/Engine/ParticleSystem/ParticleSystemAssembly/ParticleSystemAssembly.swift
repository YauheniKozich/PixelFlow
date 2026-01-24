//
//  ParticleSystemAssembly.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 24.01.26.
//

import Foundation
import MetalKit

enum ParticleSystemAssembly {
    @MainActor
    static func makeCoordinator() -> ParticleSystemCoordinator {
        guard let metalRenderer = resolve(MetalRendererProtocol.self),
              let simulationEngine = resolve(SimulationEngineProtocol.self),
              let storage = resolve(ParticleStorageProtocol.self),
              let configManager = resolve(ConfigurationManagerProtocol.self),
              let memoryManager = resolve(MemoryManagerProtocol.self),
              let generator = resolve(ParticleGeneratorProtocol.self),
              let logger = resolve(LoggerProtocol.self),
              let errorHandler = resolve(ErrorHandlerProtocol.self) else {
            fatalError("Failed to resolve ParticleSystem dependencies")
        }
        
        return ParticleSystemCoordinator(
            renderer: metalRenderer,
            simulationEngine: simulationEngine,
            storage: storage,
            configManager: configManager,
            memoryManager: memoryManager,
            generator: generator,
            logger: logger,
            errorHandler: errorHandler
        )
    }
}
