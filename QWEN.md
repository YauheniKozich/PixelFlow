# PixelFlow - Project Context

## Project Overview

**PixelFlow** is an advanced particle system framework built on Metal for iOS/macOS. It features a modular MVVM architecture, intelligent image-based particle generation, and high-performance GPU compute shaders.

### Key Characteristics

- **Platform**: iOS 16.0+, macOS 13.0+
- **Language**: Swift 5.7+
- **Graphics API**: Metal (with Metal 4 features)
- **Architecture**: MVVM with layered design (Assembly → Engine → UI)
- **Build System**: Xcode project generated via XcodeGen (`project.yml`)

### Core Capabilities

1. **Intelligent Particle Generation** - Generates particles from images using SIMD-optimized analysis, multiple sampling strategies (Uniform, Importance, Adaptive, Hybrid), and adaptive density based on image detail
2. **High-Performance Rendering** - Full Metal GPU acceleration with compute shaders for physics and vertex/fragment shaders for rendering
3. **Advanced Visual Effects** - State-based lighting, bloom/glow effects, lightning effects, cinematic lighting, HDR rendering
4. **Flexible Configuration** - Quality presets (Draft, Standard, High, Ultra), customizable particle parameters, multiple generation strategies

---

## Project Structure

```
PixelFlow/
├── 📁 Assembly/                # MVVM assembly layer
│   ├── ParticleAssembly.swift  # Component factory
│   ├── ParticleViewModel.swift # UI business logic
│   ├── ViewController.swift    # Presentation layer
│   └── RenderView.swift        # Metal render view
│
├── 📁 Engine/                  # Core simulation engine
│   ├── Generators/
│   │   └── ImageParticleGenerator/
│   │       ├── Core/           # Generator core
│   │       ├── Analysis/       # Image analysis (SIMD)
│   │       ├── Sampling/       # Pixel sampling strategies
│   │       ├── Assembly/       # Particle assembly
│   │       ├── Configuration/  # Generation config
│   │       └── Caching/        # Result caching
│   │
│   ├── ParticleSystem/
│   │   ├── Core/              # ParticleSystemController
│   │   ├── Simulation/        # Physics & state logic
│   │   ├── Rendering/         # Metal rendering
│   │   ├── Storage/           # Particle data storage
│   │   ├── Models/            # Data models
│   │   ├── ParticleSystemAssembly/  # Engine DI setup
│   │   └── Utils/             # Utilities
│   │
│   ├── Shaders/               # Metal shaders (.metal)
│   │   ├── Core/              # Common structures
│   │   ├── Compute/           # Compute shaders (physics)
│   │   ├── Rendering/         # Vertex/fragment shaders
│   │   └── Effects/           # Visual effects shaders
│   │
│   └── GraphicsUtils.swift    # Graphics helpers
│
├── 📁 Infrastructure/          # Infrastructure components
│   ├── DI/                    # Dependency injection
│   │   ├── DIContainer.swift  # DI container implementation
│   │   ├── DependencyInitializer.swift
│   │   └── *Dependencies.swift
│   ├── Protocols/             # Common protocols
│   └── Services/              # Application services
│
├── 📁 UI/                      # Application UI layer
│   ├── AppDelegate.swift      # App lifecycle
│   └── SceneDelegate.swift    # Scene lifecycle
│
├── 📁 Errors/                  # Error handling
│   ├── PixelFlowErrors.swift  # Unified error enum
│   └── ErrorHandler.swift     # Error handling logic
│
├── 📁 Resources/               # Assets & resources
│   ├── Assets.xcassets/       # App icons, images
│   └── Base.lproj/            # Storyboards, localization
│
├── 📁 Tests/                   # Unit tests (currently empty)
│
├── project.yml                 # XcodeGen configuration
├── Info.plist                  # App configuration
├── .swiftlint.yml              # SwiftLint rules
└── README.md                   # User documentation
```

---

## Building and Running

### Prerequisites

- **Xcode**: 14.0+ (recommended: latest stable)
- **Swift**: 5.7+
- **Deployment Targets**: iOS 16.0+, macOS 13.0+

### Setup

1. **Generate Xcode project** (if needed):
   ```bash
   xcodegen generate
   ```

2. **Open in Xcode**:
   ```bash
   open PixelFlow.xcodeproj
   ```

3. **Build and Run**:
   - Select target device/simulator in Xcode
   - Press `Cmd + R` to build and run

### Build Commands

| Action | Command |
|--------|---------|
| Build | `xcodebuild -project PixelFlow.xcodeproj -scheme PixelFlow build` |
| Clean Build | `xcodebuild -project PixelFlow.xcodeproj -scheme PixelFlow clean build` |
| Run Tests | `xcodebuild -project PixelFlow.xcodeproj -scheme PixelFlow test` |
| Generate Project | `xcodegen generate` |

> **Note**: The `Tests/` directory is currently empty. Test infrastructure may need to be set up.

---

## Development Conventions

### Code Style

**SwiftLint Configuration** (`.swiftlint.yml`):

- **Disabled Rules**: `trailing_whitespace`, `line_length`, `type_body_length`, `file_length`, `function_body_length`, `cyclomatic_complexity`
- **Opted-in Rules**: `force_unwrapping` (severity: error)
- **Included Paths**: `PixelFlow/`, `PixelFlowTests/`
- **Excluded Paths**: `PixelFlow.xcodeproj`, `PixelFlow.xcworkspace`, `Shaders/`, `Resources/`

### Architecture Patterns

1. **MVVM Pattern**: Clear separation between View (ViewController), ViewModel (ParticleViewModel), and Model (Engine components)

2. **Dependency Injection**: Custom DI container with two singleton containers:
   - `AppContainer.shared` - Application-level dependencies
   - `EngineContainer.shared` - Engine-specific dependencies

3. **Protocol-Oriented Design**: Heavy use of protocols for testability and flexibility:
   - `LoggerProtocol`, `ImageLoaderProtocol`, `ErrorHandlerProtocol`
   - `ParticleSystemControlling`, `ParticleGeneratorProtocol`
   - `MetalRendererProtocol`, `SimulationEngineProtocol`

4. **Thread Safety**:
   - DI container uses `NSLock` for thread-safe operations
   - ViewModel methods marked with `@MainActor`
   - Async operations use `Task` and `MainActor.run`

### Error Handling

Unified error handling via `PixelFlowError` enum with categorized errors:
- Generator errors (invalid image, analysis/sampling failures)
- Metal errors (library, buffer, pipeline creation)
- Sampling errors (cache, configuration, insufficient samples)
- Pipeline errors (invalid input/context, missing data)
- Operation errors (cancelled, timeout)
- Validation errors (particle count, screen size, image)

### Naming Conventions

- **Classes**: PascalCase (e.g., `ParticleAssembly`, `ParticleViewModel`)
- **Protocols**: PascalCase with `-ing` suffix for capabilities (e.g., `ParticleGeneratorProtocol`)
- **Enums**: PascalCase (e.g., `PixelFlowError`, `ImageDisplayMode`)
- **Files**: Match primary type name (e.g., `ParticleAssembly.swift`)

---

## Key Components Reference

### Assembly Layer (MVVM)

| Component | Purpose |
|-----------|---------|
| `ParticleAssembly` | Factory for assembling app components |
| `ParticleViewModel` | Business logic, state management, lifecycle |
| `ViewController` | UI presentation, gesture handling |

### Engine Layer

| Component | Purpose |
|-----------|---------|
| `ImageParticleGenerator` | Generate particles from images |
| `ParticleSystemController` | Main simulation coordinator |
| `MetalRenderer` | GPU rendering pipeline |
| `SimulationEngine` | Physics simulation logic |
| `ParticleStorage` | Particle data management |

### Infrastructure

| Component | Purpose |
|-----------|---------|
| `DIContainer` | Dependency injection container |
| `AppContainer` | Global app DI singleton |
| `EngineContainer` | Global engine DI singleton |
| `ErrorHandler` | Centralized error handling |

---

## Usage Examples

### Basic Assembly

```swift
// Create view controller through Assembly
let viewController = ParticleAssembly.assemble(withDI: AppContainer.shared)
```

### Direct Engine Usage

```swift
// Generate particles from image
let coordinator = GenerationCoordinatorFactory.makeCoordinator(in: EngineContainer.shared)
let config = ParticleGenerationConfig.standard

let particles = try await coordinator.generateParticles(
    from: image,
    config: config,
    screenSize: CGSize(width: 1920, height: 1080),
    progress: { progress, stage in
        print("Progress: \(progress), Stage: \(stage)")
    }
)
```

### Quality Presets

```swift
// Configure quality preset
config.quality = .high  // .draft, .standard, .high, .ultra
```

---

## Documentation References

- **[README.md](README.md)** - User-facing documentation with quick start guide
- **[Assembly](PixelFlow/Assembly/assembly.md)** - MVVM layer details
- **[Engine](PixelFlow/Engine/engine.md)** - Engine architecture overview
- **[ParticleSystem](PixelFlow/Engine/ParticleSystem/particlesystem.md)** - Particle system details
- **[ImageParticleGenerator](PixelFlow/Engine/Generators/ImageParticleGenerator/image-particle-generator.md)** - Generator documentation
- **[Shaders](PixelFlow/Engine/Shaders/shaders.md)** - Metal shader guide
- **[Infrastructure](PixelFlow/Infrastructure/infrastructure.md)** - DI and services
- **[Errors](PixelFlow/Errors/errors.md)** - Error system documentation
- **[UI](PixelFlow/UI/ui.md)** - UI layer documentation

---

## Notes for AI Assistant

1. **Language**: The codebase uses Russian comments and documentation. Keep technical terms in English but respect existing comment language when editing.

2. **Platform Support**: Code uses conditional compilation for iOS/macOS (`#if os(iOS)` / `#if os(macOS)`). Maintain cross-platform compatibility.

3. **Metal Shaders**: Shader files (`.metal`) are excluded from SwiftLint. They use Metal shading language, not Swift.

4. **Bridging Header**: Project uses a bridging header at `PixelFlow/Engine/Generators/ImageParticleGenerator/Sampling/Helpers/PixelFlow-Bridging-Header.h` for Swift/C interoperability.

5. **Empty Tests Directory**: The `Tests/` folder exists but is empty. When adding features, consider adding corresponding tests.

6. **DI Pattern**: Two-container DI system (`AppContainer` vs `EngineContainer`). Use appropriate container based on dependency scope.

7. **Main Actor**: Most public ViewModel methods are `@MainActor` annotated. Respect this pattern for UI-related code.
