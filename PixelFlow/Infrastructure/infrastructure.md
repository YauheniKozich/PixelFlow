# Infrastructure - Инфраструктурные компоненты

Инфраструктурный слой PixelFlow, предоставляющий фундаментальные сервисы: Dependency Injection, протоколы, загрузчики изображений и другие утилиты.

## Архитектура

Infrastructure слой разделен на модули:
- **DI/** - Dependency Injection контейнер
- **Protocols/** - Общие протоколы приложения
- **Services/** - Сервисы приложения

## Dependency Injection (DI)

### DIContainer
**Потокобезопасный контейнер зависимостей**

```swift
final class DIContainer: DIContainerProtocol {
    private var services = [ServiceKey: Any]()
    private let lock = NSLock()

    func register<T>(_ service: T, for type: T.Type = T.self, name: String? = nil)
    func resolve<T>(_ type: T.Type = T.self, name: String? = nil) -> T?
    func isRegistered<T>(_ type: T.Type = T.self, name: String? = nil) -> Bool
}
```

**Особенности:**
- Thread-safe с использованием `NSLock`
- Поддержка именованных сервисов
- Типобезопасность через generics

### AppContainer
**Глобальный singleton контейнер**

```swift
final class AppContainer {
    static let shared = DIContainer()
}

// Удобные глобальные функции
func resolve<T>(_ type: T.Type = T.self, name: String? = nil) -> T?
func register<T>(_ service: T, for type: T.Type = T.self, name: String? = nil)
func isRegistered<T>(_ type: T.Type = T.self, name: String? = nil) -> Bool
```

**Инициализация:**
```swift
// В AppDelegate или раннем этапе
register(Logger.shared, for: LoggerProtocol.self)
register(ImageLoader(), for: ImageLoaderProtocol.self)
```

## Протоколы

### DIProtocols
**Протоколы для DI системы**

```swift
protocol DIContainerProtocol {
    func register<T>(_ service: T, for type: T.Type, name: String?)
    func resolve<T>(_ type: T.Type, name: String?) -> T?
    func isRegistered<T>(_ type: T.Type, name: String?) -> Bool
}
```

### LoggingProtocols
**Протоколы для логирования**

```swift
public protocol LoggerProtocol: Sendable {
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
    func debug(_ message: String)
}
```

### GeneratorProtocols
**Протоколы для генераторов частиц**

```swift
protocol GenerationCoordinatorProtocol {
    func generateParticles(from image: CGImage,
                          config: ParticleGenerationConfig,
                          screenSize: CGSize,
                          progress: ((Double, GenerationStage) -> Void)?) async throws -> [Particle]
}

protocol ParticleGenerationDelegate: AnyObject {
    func generationDidStart()
    func generationDidProgress(_ progress: Double, stage: GenerationStage)
    func generationDidComplete(_ particles: [Particle])
    func generationDidFail(_ error: Error)
}
```

### MetalProtocols
**Протоколы для Metal компонентов**

```swift
protocol MetalRendererProtocol {
    func setupPipelines() throws
    func setupBuffers(particleCount: Int) throws
    func encodeCompute(into buffer: MTLCommandBuffer)
    // ...
}

protocol SimulationEngineProtocol {
    var state: SimulationState { get }
    var clock: SimulationClock { get }
    func updateSimulation()
    // ...
}
```

### ParticleSystemProtocols
**Протоколы для системы частиц**

```swift
protocol ParticleSystemAdapterProtocol {
    var particleCount: Int { get }
    var hasActiveSimulation: Bool { get }
    var isHighQuality: Bool { get }

    func toggleState()
    func startSimulation()
    func initializeWithFastPreview()
    func replaceWithHighQualityParticles(completion: @escaping (Bool) -> Void)
}
```

## Сервисы

### Logger
**Сервис логирования (Infrastructure/Services/Logger.swift)**

```swift
public final class Logger {
    public static let shared = Logger()
    // ...
}
```

### ImageLoader
**Сервис загрузки изображений**

```swift
protocol ImageLoaderProtocol {
    func loadImageWithFallback() -> CGImage?
}

class ImageLoader: ImageLoaderProtocol {
    func loadImageWithFallback() -> CGImage? {
        // 1. Попытка загрузки из бандла (steve.png)
        // 2. Генерация тестового изображения при неудаче
    }
}
```

**Функциональность:**
- Загрузка изображений из asset catalog
- Fallback к генерации тестового изображения
- Поддержка разных форматов (PNG, JPEG)

## Архитектурные принципы

### Чистая архитектура
Infrastructure слой обеспечивает:
- **Независимость модулей** через протоколы
- **Тестируемость** через dependency injection
- **Расширяемость** через интерфейсы

### Протокольно-ориентированный дизайн
- Все компоненты описаны протоколами
- Легкая замена реализаций
- Поддержка моков для тестирования

### Потокобезопасность
- DI контейнер thread-safe
- Асинхронные операции с правильной изоляцией
- Безопасный доступ к shared ресурсам

## Использование

### Регистрация зависимостей
```swift
// В startup коде (AppContainer)
register(Logger.shared, for: LoggerProtocol.self)
register(ImageLoader(), for: ImageLoaderProtocol.self)

// В engine-коде (EngineContainer)
registerEngine(GenerationCoordinatorFactory.makeCoordinator(),
               for: GenerationCoordinatorProtocol.self)
```

### Разрешение зависимостей
```swift
// В классах
init() {
    guard let logger = resolve(LoggerProtocol.self),
          let imageLoader = resolve(ImageLoaderProtocol.self) else {
        fatalError("Failed to resolve dependencies")
    }
    self.logger = logger
    self.imageLoader = imageLoader
}
```

## Тестирование

Infrastructure поддерживает тестирование:
- **Моки** для протоколов
- **Тестовые реализации** сервисов
- **Изоляция зависимостей** через DI

```swift
// Пример тестового setup
let mockLogger = MockLogger()
register(mockLogger, for: LoggerProtocol.self)

// Тестируемый объект будет использовать mock
let viewModel = ParticleViewModel(
    logger: logger,
    imageLoader: imageLoader,
    errorHandler: errorHandler,
    renderViewFactory: { frame in
        ParticleSystemFactory.makeRenderView(frame: frame)
    },
    systemFactory: { view in
        ParticleSystemFactory.makeController(for: view)
    }
)
