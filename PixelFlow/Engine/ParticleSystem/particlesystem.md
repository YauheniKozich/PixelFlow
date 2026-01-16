# ParticleSystem - Детальная документация

Подробное описание системы симуляции частиц PixelFlow, включая все компоненты и их взаимодействие.

## Архитектура

ParticleSystem построен на модульной архитектуре с четким разделением ответственности:

```
ParticleSystem/
├── Core/              # Основные компоненты и адаптеры
├── Simulation/        # Логика симуляции и физики
├── Rendering/         # Metal рендеринг и шейдеры
├── Particles/         # Структуры данных частиц
├── Models/            # Модели и конфигурации
├── Storage/           # Управление данными и конфигурацией
├── Utils/             # Вспомогательные функции
└── Extension/         # Расширения типов
```

## Core - Основные компоненты

### ParticleSystemAdapter
**Адаптер для совместимости с существующим API**

**Назначение:**
- Обеспечивает совместимость между новой архитектурой и старым API
- Управляет жизненным циклом компонентов
- Координирует Metal рендеринг и симуляцию

**Ключевые свойства:**
```swift
var enableIdleChaotic: Bool = true          // Хаотичное движение в idle
let device: MTLDevice                        // Metal device
let commandQueue: MTLCommandQueue            // Командная очередь
let particleCount: Int                       // Количество частиц
var hasActiveSimulation: Bool                // Активна ли симуляция
var isHighQuality: Bool                      // Используются ли HQ частицы
```

**Основные методы:**
```swift
func toggleState()                           // Переключение пауза/воспроизведение
func startSimulation()                       // Запуск симуляции
func startLightningStorm()                   // Специальный эффект молний
func initializeWithFastPreview()             // Быстрый превью режим
func replaceWithHighQualityParticles()       // Замена на HQ частицы
func cleanup()                               // Очистка ресурсов
```

### ParticleSystemCoordinator
**Главный координатор системы**

**Функциональность:**
- Управление конфигурацией и состоянием
- Координация между генераторами и рендерером
- Управление кэшированием и оптимизациями
- Обработка асинхронных операций генерации

## Simulation - Логика симуляции

### SimulationEngine
**Движок симуляции частиц**

**Состояния симуляции:**
```swift
enum SimulationState {
    case idle           // Частицы в покое с хаотичным движением
    case chaotic        // Хаотичное движение всех частиц
    case collecting     // Частицы собираются в центр
    case collected      // Частицы собраны, ждут команды
}
```

**Ключевые компоненты:**
- **SimulationClock**: Управление временем и delta-time
- **SimulationStateMachine**: Конечный автомат состояний
- **SimulationParamsUpdater**: Обновление параметров для GPU

### SimulationStateMachine
**Конечный автомат состояний**

**Переходы состояний:**
```
idle → chaotic → collecting → collected → idle
   ↑                                    ↓
   └────────────────────────────────────┘
```

**Логика переходов:**
- **idle**: Частицы слегка колеблются
- **chaotic**: Все частицы в хаотичном движении
- **collecting**: Частицы притягиваются к центру
- **collected**: Частицы в плотной группе

### SimulationClock
**Управление временем симуляции**

```swift
struct SimulationClock {
    var currentTime: Double              // Текущее время
    var deltaTime: Float                 // Время кадра
    var timeSinceStart: Double           // Время с начала симуляции
    var isPaused: Bool                   // Пауза симуляции
}
```

## Rendering - Metal рендеринг

### MetalRenderer
**Metal рендерер для GPU вычислений и отрисовки**

**Pipeline:**
- **Compute Pipeline**: Обновление позиций частиц на GPU
- **Render Pipeline**: Отрисовка частиц как точек

**Ключевые методы:**
```swift
func setupPipelines() throws              // Настройка Metal pipelines
func setupBuffers(particleCount: Int)    // Создание буферов
func encodeCompute(into: MTLCommandBuffer) // Кодирование compute команд
func draw(in: MTKView)                    // Отрисовка кадра
```

**Особенности:**
- Использование `updateParticles` compute шейдера
- Point primitive рендеринг частиц
- Alpha blending для прозрачности
- HDR эффекты через цветовые компоненты

## Particles - Структуры данных

### Particle
**Основная структура частицы**

**Память (80 байт):**
```swift
struct Particle {
    // Позиция и движение (48 байт)
    var position: SIMD3<Float>           // Текущая позиция
    var velocity: SIMD3<Float>           // Скорость
    var targetPosition: SIMD3<Float>     // Целевая позиция

    // Цвета (32 байта)
    var color: SIMD4<Float>              // Текущий цвет (RGBA)
    var originalColor: SIMD4<Float>      // Исходный цвет

    // Свойства (16 байт)
    var size: Float                      // Размер частицы
    var baseSize: Float                  // Базовый размер
    var life: Float                      // Время жизни
    var idleChaoticMotion: UInt32        // Флаг хаотичного движения
}
```

**Выравнивание:** 16-байтное для SIMD оптимизаций

### ParticleConstants
**Константы для частиц**

```swift
struct ParticleConstants {
    static let maxParticleCount = 300_000
    static let minSize: Float = 1.0
    static let maxSize: Float = 6.0
    static let defaultLife: Float = 0.0
}
```

## Models - Модели данных

### SimulationParams
**Параметры симуляции для GPU (256 байт)**

```swift
struct SimulationParams {
    var state: UInt32                    // Текущее состояние
    var pixelSizeMode: UInt32            // Режим размеров
    var colorsLocked: UInt32             // Блокировка цветов
    var deltaTime: Float                 // Время кадра

    var collectionSpeed: Float           // Скорость сбора
    var brightnessBoost: Float = 1       // Усиление яркости
    var screenSize: SIMD2<Float>         // Размер экрана

    // Размеры частиц
    var minParticleSize: Float = 1       // Мин размер
    var maxParticleSize: Float = 6       // Макс размер
    var time: Float                      // Текущее время
    var particleCount: UInt32            // Количество частиц

    // + padding до 256 байт
}
```

**Критически важно:** Размер ровно 256 байт для Metal буферов

## Storage - Управление данными

### ConfigManager
**Менеджер конфигураций**

**Функциональность:**
- Хранение и загрузка конфигураций
- Валидация параметров
- Управление пресетами качества

### ParticleStorage
**Хранение данных частиц**

**Особенности:**
- Потокобезопасное хранение
- Эффективная сериализация/десериализация
- Управление памятью для больших массивов

## Utils - Вспомогательные функции

### Logger
**Система логирования**

```swift
protocol LoggerProtocol {
    func debug(_ message: String)
    func info(_ message: String)
    func warning(_ message: String)
    func error(_ message: String)
}
```

### MemoryManager
**Управление памятью**

**Функции:**
- Мониторинг использования памяти
- Очистка неиспользуемых ресурсов
- Оптимизация под ограничения устройства

### State+ShaderValue
**Расширения для конвертации состояний в шейдерные значения**

```swift
extension SimulationState {
    var shaderValue: UInt32 {
        switch self {
        case .idle: return 0
        case .chaotic: return 1
        case .collecting: return 2
        case .collected: return 3
        }
    }
}
```

## Взаимодействие компонентов

```
App → ParticleSystemAdapter → ParticleSystemCoordinator
                              ↓
                    SimulationEngine ← MetalRenderer
                              ↓
                        GPU Shaders (Metal)
                              ↓
                    MTKView → Display
```

## Производительность

### Оптимизации
- **GPU acceleration**: Все вычисления на Metal
- **SIMD**: Векторизованные операции
- **Memory pooling**: Переиспользование буферов
- **Async processing**: Фоновая генерация HQ частиц

### Метрики
- **Целевой FPS**: 60 FPS
- **Максимум частиц**: 300,000
- **Память**: ~24MB для 100k частиц
- **CPU использование**: <5% на симуляцию

## Расширение системы

ParticleSystem спроектирован для расширения:
- **Новые состояния**: Добавление через SimulationStateMachine
- **Эффекты**: Новые шейдеры в Effects/
- **Генераторы**: Плагины через GenerationCoordinatorProtocol
- **Рендереры**: Альтернативные бэкенды через RendererProtocol