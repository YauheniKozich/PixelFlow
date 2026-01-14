# План рефакторинга архитектуры PixelFlow

## 1. Рефакторинг ParticleSystem (Приоритет: Высокий)

### Текущие проблемы:
- Нарушение SRP: управление Metal, симуляцией, генерацией, состоянием
- Сильная связанность с компонентами
- Циклические зависимости

### Предлагаемое решение:

#### 1.1 Разделить на отдельные компоненты:

```
ParticleSystem/
├── Core/
│   ├── ParticleSystemCoordinator.swift  # Главный координатор
│   ├── ParticleSystemProtocol.swift     # Протокол
│   └── ParticleSystemFactory.swift      # Фабрика создания
├── Rendering/
│   ├── MetalRenderer.swift              # Управление Metal
│   ├── PipelineManager.swift            # Управление pipeline
│   └── BufferManager.swift              # Управление буферами
├── Simulation/
│   ├── ParticleSimulator.swift          # Логика симуляции
│   ├── StateManager.swift               # Управление состояниями
│   └── PhysicsEngine.swift              # Физика частиц
└── Storage/
    ├── ParticleStorage.swift            # Хранение частиц
    └── ConfigManager.swift              # Управление конфигурацией
```

#### 1.2 Ввести протоколы для разделения:

```swift
protocol ParticleSystemCoordinator {
    func startSimulation()
    func stopSimulation()
    func updateConfiguration(_ config: ParticleConfig)
}

protocol MetalRendererProtocol {
    func setupPipelines(device: MTLDevice) throws
    func renderParticles(in view: MTKView, at time: CFTimeInterval)
}

protocol SimulationEngine {
    func updateParticles(deltaTime: Float)
    func applyForces()
}
```

#### 1.3 Убрать циклические зависимости:
- Использовать weak ссылки или протоколы
- Ввести event-driven архитектуру для коммуникации

## 2. Улучшение ImageParticleGenerator (Приоритет: Высокий)

### Текущие проблемы:
- Слишком большой класс (569 строк)
- Смешивание ответственностей координатора и исполнителя
- Сложная логика очистки

### Предлагаемое решение:

#### 2.1 Выделить компоненты:

```
ImageParticleGenerator/
├── Core/
│   ├── GenerationCoordinator.swift      # Координатор
│   ├── GenerationPipeline.swift         # Pipeline генерации
│   └── GenerationContext.swift          # Контекст генерации
├── Managers/
│   ├── MemoryManager.swift              # Управление памятью
│   ├── OperationManager.swift           # Управление операциями
│   └── CacheManager.swift               # Кэширование (уже есть)
├── Services/
│   ├── ImageAnalysisService.swift       # Сервис анализа
│   ├── SamplingService.swift            # Сервис сэмплинга
│   └── AssemblyService.swift            # Сервис сборки
└── Utils/
    ├── GenerationMetrics.swift          # Метрики производительности
    └── ResourceTracker.swift            # Отслеживание ресурсов
```

#### 2.2 Упростить API:

```swift
protocol ParticleGenerationService {
    func generateParticles(
        from image: CGImage,
        config: GenerationConfig,
        progress: @escaping (Float) -> Void
    ) async throws -> [Particle]
}

class DefaultGenerationService: ParticleGenerationService {
    private let analyzer: ImageAnalyzer
    private let sampler: PixelSampler
    private let assembler: ParticleAssembler
    private let memoryManager: MemoryManager

    // Dependency injection
    init(analyzer: ImageAnalyzer, sampler: PixelSampler, ...) {
        // ...
    }
}
```

## 3. Введение Dependency Injection (Приоритет: Высокий)

### Текущие проблемы:
- Зависимости создаются в init
- Нет возможности замены компонентов
- Сложно тестировать

### Предлагаемое решение:

#### 3.1 Создать DI контейнер:

```swift
protocol DIContainer {
    func resolve<T>() -> T
}

class AppDIContainer: DIContainer {
    private var services = [String: Any]()

    func register<T>(_ service: T, for type: T.Type = T.self) {
        let key = String(describing: T.self)
        services[key] = service
    }

    func resolve<T>() -> T {
        let key = String(describing: T.self)
        guard let service = services[key] as? T else {
            fatalError("Service \(T.self) not registered")
        }
        return service
    }
}
```

#### 3.2 Настроить инъекцию в Assembly:

```swift
class ParticleAssembly {
    private let container: DIContainer

    func assemble() -> UIViewController {
        // Регистрация сервисов
        container.register(ImageAnalysisService() as ImageAnalyzer)
        container.register(PixelSamplingService() as PixelSampler)
        // ...

        let viewModel = ParticleViewModel(
            imageLoader: container.resolve(),
            particleGenerator: container.resolve(),
            configManager: container.resolve()
        )

        return ViewController(viewModel: viewModel)
    }
}
```

## 4. Решение проблем памяти и потокобезопасности (Приоритет: Средний)

### Текущие проблемы:
- Ручное управление памятью в Metal
- Потенциальные гонки в очередях
- Утечки памяти при отмене операций

### Предлагаемое решение:

#### 4.1 Ввести Resource Manager:

```swift
protocol ResourceManager {
    func allocateBuffer<T>(for type: T.Type, count: Int) -> MTLBuffer?
    func deallocateBuffer(_ buffer: MTLBuffer)
    func trackMemoryUsage()
}

class MetalResourceManager: ResourceManager {
    private var allocatedBuffers = Set<MTLBuffer>()
    private let lock = NSLock()

    func allocateBuffer<T>(for type: T.Type, count: Int) -> MTLBuffer? {
        lock.lock()
        defer { lock.unlock() }

        guard let device = MTLCreateSystemDefaultDevice() else { return nil }

        let buffer = device.makeBuffer(
            length: MemoryLayout<T>.stride * count,
            options: .storageModeShared
        )

        if let buffer = buffer {
            allocatedBuffers.insert(buffer)
        }

        return buffer
    }

    func deallocateBuffer(_ buffer: MTLBuffer) {
        lock.lock()
        defer { lock.unlock() }

        allocatedBuffers.remove(buffer)
        // Metal автоматически управляет памятью
    }
}
```

#### 4.2 Улучшить потокобезопасность:

```swift
actor GenerationCoordinator {
    private var state: GenerationState = .idle
    private let operationQueue: OperationQueue

    func startGeneration(config: GenerationConfig) async throws -> [Particle] {
        guard state == .idle else {
            throw GenerationError.alreadyRunning
        }

        state = .running

        defer { state = .idle }

        return try await withCheckedThrowingContinuation { continuation in
            let operation = GenerationOperation(config: config) { result in
                switch result {
                case .success(let particles):
                    continuation.resume(returning: particles)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }

            operationQueue.addOperation(operation)
        }
    }
}
```

## 5. Улучшение тестируемости (Приоритет: Средний)

### Текущие проблемы:
- Классы плотно связаны
- Зависимости от Metal и UIKit
- Сложно мокать системные компоненты

### Предлагаемое решение:

#### 5.1 Создать протоколы для всех зависимостей:

```swift
protocol MetalDevice {
    func makeBuffer(length: Int, options: MTLResourceOptions) -> MTLBuffer?
    func makeCommandQueue() -> MTLCommandQueue?
    // ...
}

protocol ImageLoader {
    func loadImage(named name: String) -> CGImage?
}

protocol FileManager {
    func createTemporaryDirectory() -> URL
    func removeItem(at url: URL) throws
}
```

#### 5.2 Ввести TestAssembly:

```swift
class TestAssembly {
    static func createTestContainer() -> DIContainer {
        let container = AppDIContainer()

        // Регистрация моков
        container.register(MockMetalDevice() as MetalDevice)
        container.register(MockImageLoader() as ImageLoader)
        container.register(MockFileManager() as FileManager)

        return container
    }
}
```

## 6. План внедрения

### Фаза 1: Подготовка (1-2 недели)
1. Создать протоколы для всех основных компонентов
2. Настроить DI контейнер
3. Создать базовые тесты

### Фаза 2: Рефакторинг ядра (2-3 недели)
1. Разделить ParticleSystem на компоненты
2. Рефакторить ImageParticleGenerator
3. Ввести новые протоколы

### Фаза 3: Интеграция и тестирование (1-2 недели)
1. Интегрировать DI во все компоненты
2. Написать unit-тесты
3. Провести интеграционное тестирование

### Фаза 4: Оптимизация (1 неделя)
1. Профилирование производительности
2. Оптимизация памяти
3. Финальное тестирование

## 7. Риски и mitigation

### Риски:
- Регрессии в производительности
- Утечки памяти при рефакторинге
- Сложность интеграции DI

### Mitigation:
- Постепенное внедрение с фиче-флагами
- Обширное тестирование
- Профилирование на каждом этапе

## 8. Метрики успеха

- Уменьшение размера классов на 50%
- Увеличение покрытия тестами до 80%
- Снижение количества зависимостей на класс
- Улучшение времени сборки и запуска
- Упрощение добавления новых фич