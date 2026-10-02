# Infrastructure

Infrastructure contains shared service interfaces and implementations used by the app composition root and runtime components.

## Structure

- `Protocols/LoggingProtocols.swift` defines the logger boundary.
- `Protocols/GeneratorProtocols.swift` defines the active image-generation pipeline boundaries.
- `Protocols/ParticleSystemProtocols.swift` defines the active particle-system, renderer, storage, and service boundaries.
- `Services/` contains app services such as `Logger` and `ImageLoader`.

## Composition and ownership

`AppCompositionRoot` creates shared app services and explicitly passes them to presentation and engine objects. Each particle view receives a separate storage, simulation, renderer, controller, and generation coordinator. Infrastructure services do not resolve dependencies globally or retain view-specific objects.

`Logger.shared` is used at app bootstrap and as the composition root's default logger. Runtime objects that receive a logger use that injected instance.

## Shared services

- `ImageLoader` loads bundled or remote images and creates the fallback image.
- `ErrorHandler` reports errors and applies recovery strategies.
- `MemoryManager` tracks aggregate app memory use behind a lock and observes low-memory notifications.
- `DefaultCacheManager` serializes index and cache-file access on a barrier queue.

The composition root owns these shared services for the app lifetime. Mutable view and generation state stays within each particle-system graph.
