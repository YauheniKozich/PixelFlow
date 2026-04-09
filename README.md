# PixelFlow - Система частиц на Metal

Модульная система частиц на Metal для iOS с MVVM-архитектурой, генерацией частиц из изображений и GPU-вычислениями.

## Быстрый старт

```swift
// Создание приложения через Assembly (MVVM паттерн)
let viewController = ParticleAssembly.assemble(withDI: AppContainer.shared)
// Или прямая работа с Engine
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

## Архитектура проекта

PixelFlow состоит из нескольких модулей:
- `Assembly` собирает UI, ViewModel и зависимости
- `Engine` содержит генераторы, симуляцию и Metal-шейдеры
- `UI` управляет жизненным циклом приложения
- `Infrastructure` хранит DI, протоколы и сервисы
- `Resources` содержит ассеты и локализацию

Подробности по каждому модулю находятся в отдельных markdown-файлах.

```
PixelFlow/
├── 📁 Assembly/                # MVVM слой сборки
│   ├── ParticleAssembly.swift  # Фабрика компонентов
│   ├── ParticleViewModel.swift # Бизнес-логика UI
│   └── ViewController.swift    # Презентационный слой
│
├── 📁 Engine/                 # Ядро симуляции частиц
│   ├── Generators/            # Генерация частиц из изображений
│   │   └── ImageParticleGenerator/
│   │       ├── Core/           # Ядро генератора
│   │       ├── Analysis/       # Анализ изображений
│   │       ├── Sampling/       # Сэмплинг пикселей
│   │       ├── Assembly/       # Сборка частиц
│   │       ├── Configuration/  # Конфигурация
│   │       └── Caching/        # Кэширование
│   │
│   ├── ParticleSystem/        # Система симуляции частиц
│   │   ├── Core/              # Основные компоненты
│   │   ├── Simulation/        # Логика симуляции
│   │   ├── Rendering/         # Metal рендеринг
│   │   ├── Particles/         # Структуры данных
│   │   ├── Models/            # Модели данных
│   │   ├── Extension/         # Расширения
│   │   └── Utils/             # Утилиты
│   │
│   ├── Shaders/               # Metal шейдеры
│   │   ├── Core/              # Общие структуры
│   │   ├── Compute/           # Вычислительные шейдеры
│   │   ├── Rendering/         # Рендеринг шейдеры
│   │   ├── Effects/           # Визуальные эффекты
│   │   └── ParticleShader.metal # Главный шейдер
│   │
│   └── GraphicsUtils.swift    # Графические утилиты
│
├── 📁 UI/                     # Пользовательский интерфейс iOS
│   ├── AppDelegate.swift      # Делегат приложения
│   └── SceneDelegate.swift    # Делегат сцены
│
├── 📁 Infrastructure/         # Инфраструктурные компоненты
│   ├── DI/                    # Внедрение зависимостей
│   ├── Protocols/             # Общие протоколы
│   └── Services/              # Сервисы приложения
│
├── 📁 Resources/              # Ресурсы и ассеты
│   ├── Assets.xcassets/       # Иконки и изображения
│   └── Base.lproj/            # Storyboards и локализация
```

## Ключевые возможности

- Генерация частиц из изображений
- Симуляция и рендеринг на Metal
- MVVM-сборка через `Assembly`
- Presets качества: Draft, Standard, High, Ultra
- State-based эффекты освещения

## Документация

### Быстрый старт
- **[ImageParticleGenerator](PixelFlow/Engine/Generators/ImageParticleGenerator/image-particle-generator.md)** - Руководство по генерации частиц

### Архитектура проекта
- **[Assembly](PixelFlow/Assembly/assembly.md)** - MVVM слой и сборка
- **[UI](PixelFlow/UI/ui.md)** - AppDelegate, SceneDelegate, ViewController
- **[Infrastructure](PixelFlow/Infrastructure/infrastructure.md)** - DI, протоколы, сервисы
- **[Errors](PixelFlow/Errors/errors.md)** - Система ошибок PixelFlow
- **[Resources](PixelFlow/Resources/resources.md)** - Ассеты, локализация, управление ресурсами

### Engine - Ядро симуляции
- **[Engine Overview](PixelFlow/Engine/engine.md)** - Архитектура и компоненты Engine
- **[ParticleSystem Details](PixelFlow/Engine/ParticleSystem/particlesystem.md)** - Детальная документация ParticleSystem

### Генерация частиц
- **[ImageParticleGenerator](PixelFlow/Engine/Generators/ImageParticleGenerator/image-particle-generator.md)** - Детальное руководство по генератору частиц
- **[Core](PixelFlow/Engine/Generators/ImageParticleGenerator/Core/core.md)** - Ядро генератора
- **[Analysis](PixelFlow/Engine/Generators/ImageParticleGenerator/Analysis/analysis.md)** - Анализ изображений
- **[Sampling](PixelFlow/Engine/Generators/ImageParticleGenerator/Sampling/sampling.md)** - Стратегии сэмплинга
- **[Strategies](PixelFlow/Engine/Generators/ImageParticleGenerator/Strategies/strategies.md)** - Стратегии генерации
- **[Assembly](PixelFlow/Engine/Generators/ImageParticleGenerator/Assembly/assembly.md)** - Сборка частиц
- **[Caching](PixelFlow/Engine/Generators/ImageParticleGenerator/Caching/caching.md)** - Система кэширования

### Metal шейдеры
- **[Shaders Guide](PixelFlow/Engine/Shaders/shaders.md)** - Структура Metal шейдеров
- **[Shader Usage](PixelFlow/Engine/Shaders/Shader-Usage-Guide.md)** - Практическое использование шейдеров
- **[Metal 4 Features](PixelFlow/Engine/Shaders/metal.md)** - Возможности Metal 4


## Системные требования

- **Платформа**: iOS target
- **Xcode**: current project-compatible version with Metal toolchain
- **Swift**: 5.0 as set in the Xcode project

## Лицензия

MIT License - см. файл LICENSE

---
