# План рефакторинга ImageParticleGenerator

## Анализ текущей архитектуры

### Проблемы текущего ImageParticleGenerator:
- **Размер класса**: 569 строк - слишком большой для одной ответственности
- **Нарушение SRP**: класс делает анализ, сэмплинг, сборку, кэширование, управление памятью
- **Сильные зависимости**: сложно тестировать и модифицировать
- **Смешивание уровней**: бизнес-логика + инфраструктура + управление состоянием

### Текущие ответственности:
1. **Координация генерации** - главный процесс
2. **Управление состоянием** - isGenerating, progress, stage
3. **Работа с очередями** - OperationQueue, async operations
4. **Управление памятью** - MemoryManager, cleanup
5. **Кэширование** - CacheManager
6. **Анализ изображений** (делегирует существующему компоненту)
7. **Сэмплинг пикселей** (делегирует существующему компоненту)
8. **Сборка частиц** (делегирует существующему компоненту)

## Предлагаемая новая архитектура

### Компоненты для разделения:

```
ImageParticleGenerator (новая архитектура)
├── Core/
│   ├── GenerationCoordinator.swift       # Главный координатор ⭐
│   ├── GenerationPipeline.swift          # Конвейер генерации ⭐
│   └── GenerationContext.swift           # Контекст генерации ⭐
├── Managers/
│   ├── OperationManager.swift            # Управление операциями ⭐
│   ├── MemoryManager.swift               # Управление памятью (уже есть)
│   └── CacheManager.swift                # Кэширование (уже есть)
├── Strategies/
│   ├── GenerationStrategy.swift          # Стратегии генерации ⭐
│   └── SequentialStrategy.swift          # Последовательная стратегия ⭐
├── Analysis/ (существующие компоненты)
├── Sampling/ (существующие компоненты)
└── Assembly/ (существующие компоненты)
```

### 1. GenerationCoordinator - Главный координатор
**Ответственность:** Оркестрация всего процесса генерации, управление жизненным циклом

**Протокол:**
```swift
protocol GenerationCoordinatorProtocol {
    func generateParticles(from image: CGImage, config: ParticleGenerationConfig,
                          progress: @escaping (Float, String) -> Void) async throws -> [Particle]
    func cancelGeneration()
    var isGenerating: Bool { get }
}
```

**Зависимости:**
- GenerationPipelineProtocol
- OperationManagerProtocol
- MemoryManagerProtocol
- LoggerProtocol

### 2. GenerationPipeline - Конвейер генерации
**Ответственность:** Управление последовательностью этапов генерации

**Протокол:**
```swift
protocol GenerationPipelineProtocol {
    func execute(image: CGImage, config: ParticleGenerationConfig,
                progress: @escaping (Float, String) -> Void) async throws -> [Particle]
    func executeStage(_ stage: GenerationStage, input: GenerationStageInput,
                     config: ParticleGenerationConfig) async throws -> GenerationStageOutput
}
```

**Этапы конвейера:**
1. **Analysis** - анализ изображения (ImageAnalyzer)
2. **Sampling** - выбор пикселей (PixelSampler)
3. **Assembly** - сборка частиц (ParticleAssembler)
4. **Caching** - сохранение в кэш (CacheManager)

### 3. OperationManager - Менеджер операций
**Ответственность:** Управление асинхронными операциями, очередями, отменой

**Протокол:**
```swift
protocol OperationManagerProtocol {
    func execute<T: Sendable>(_ operation: @escaping () async throws -> T) async throws -> T
    func cancelAll()
    var hasActiveOperations: Bool { get }
}
```

### 4. GenerationContext - Контекст генерации
**Ответственность:** Хранение состояния генерации, промежуточных данных

```swift
protocol GenerationContextProtocol {
    var image: CGImage? { get set }
    var config: ParticleGenerationConfig { get set }
    var analysis: ImageAnalysis? { get set }
    var samples: [Sample] { get set }
    var particles: [Particle] { get set }
    var progress: Float { get set }
    var currentStage: String { get set }
    func reset()
}
```

## Стратегии генерации

### 1. SequentialStrategy - Последовательная
- Все этапы выполняются последовательно
- Минимальные ресурсы, максимальная надежность

### 2. ParallelStrategy - Параллельная
- Анализ и сэмплинг могут выполняться параллельно
- Требует больше ресурсов, выше производительность

### 3. AdaptiveStrategy - Адаптивная
- Автоматический выбор стратегии на основе размера изображения и конфигурации
- Баланс между скоростью и надежностью

## DI Интеграция

### Регистрация зависимостей:
```swift
class ImageGeneratorDependencies {
    static func register(in container: DIContainer) {
        // Координаторы
        container.register(GenerationCoordinator.self, for: GenerationCoordinatorProtocol.self)

        // Конвейеры
        container.register(GenerationPipeline.self, for: GenerationPipelineProtocol.self)

        // Менеджеры
        container.register(OperationManager.self, for: OperationManagerProtocol.self)
        container.register(MemoryManager.self, for: MemoryManagerProtocol.self)
        container.register(CacheManager.self, for: CacheManagerProtocol.self)

        // Существующие компоненты
        container.register(DefaultImageAnalyzer.self, for: ImageAnalyzerProtocol.self)
        container.register(DefaultPixelSampler.self, for: PixelSamplerProtocol.self)
        container.register(DefaultParticleAssembler.self, for: ParticleAssemblerProtocol.self)
    }
}
```

## План миграции

### Фаза 1: Подготовка (1 неделя)
1. ✅ Создать протоколы для новых компонентов
2. ✅ Настроить DI для генераторов
3. ✅ Создать базовые реализации компонентов

### Фаза 2: Реализация компонентов (2 недели)
1. **GenerationCoordinator** - главный координатор
2. **GenerationPipeline** - конвейер этапов
3. **OperationManager** - управление операциями
4. **GenerationContext** - контекст генерации
5. **Стратегии генерации** - различные подходы

### Фаза 3: Интеграция (1 неделя)
1. **ImageParticleGeneratorAdapter** - адаптер для совместимости
2. **Обновление ParticleSystemCoordinator** - интеграция с новым генератором
3. **Миграция тестов** - обновление существующих тестов

### Фаза 4: Тестирование и оптимизация (1 неделя)
1. **Интеграционные тесты** - проверка взаимодействия
2. **Профилирование производительности** - сравнение с текущей реализацией
3. **Оптимизация** - улучшение производительности

## Преимущества новой архитектуры

### 1. **Модульность**
- Каждый компонент имеет четкую ответственность
- Легко заменять реализации (например, разные стратегии генерации)

### 2. **Тестируемость**
- Все зависимости инжектируются
- Легко мокать компоненты для unit-тестов

### 3. **Расширяемость**
- Легко добавлять новые этапы генерации
- Поддержка разных стратегий выполнения

### 4. **Производительность**
- Параллельное выполнение независимых этапов
- Адаптивные стратегии для разных сценариев

### 5. **Поддерживаемость**
- Четкое разделение ответственностей
- Маленькие, фокусированные компоненты

## Риски и mitigation

### Риски:
- **Регрессия производительности** - новая архитектура может быть медленнее
- **Сложность отладки** - распределенная логика сложнее отлаживать
- **Проблемы с потокобезопасностью** - асинхронные операции

### Mitigation:
- **Инкрементальная миграция** - постепенный переход с адаптерами
- **Обширное тестирование** - интеграционные тесты на производительность
- **Мониторинг и метрики** - отслеживание ключевых показателей

## Метрики успеха

- **Снижение размера основного класса** на 70%
- **Увеличение покрытия тестами** до 95%
- **Сохранение или улучшение производительности**
- **Упрощение добавления новых функций**
- **Снижение количества багов** в генерации частиц