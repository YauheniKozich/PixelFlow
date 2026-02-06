# Assembly - MVVM слой сборки

MVVM архитектурный слой PixelFlow, отвечающий за сборку компонентов, управление жизненным циклом и связь между UI и Engine.

## Архитектура MVVM

PixelFlow использует паттерн Model-View-ViewModel (MVVM) для разделения ответственности:

- **Model**: Engine компоненты (ParticleSystem, Generators)
- **View**: UIViewController и UI элементы
- **ViewModel**: ParticleViewModel - бизнес-логика и состояние

## Основные компоненты

### ParticleAssembly
**Фабрика компонентов для сборки приложения**

```swift
final class ParticleAssembly {
    // MARK: - Public Methods

    static func assemble() -> PlatformViewController {
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

        #if os(iOS)
        let viewController = ViewController(viewModel: viewModel)
        #elseif os(macOS)
        let viewController = MacViewController(viewModel: viewModel)
        #endif

        return viewController
    }

    static func makeSceneDelegate() -> PlatformSceneDelegate {
        #if os(iOS)
        return SceneDelegate()
        #elseif os(macOS)
        return MacSceneDelegate()
        #endif
    }
}
```

**Особенности:**
- Кроссплатформенная поддержка (iOS/macOS)
- Упрощенная сборка через статические методы
- Автоматическое разрешение зависимостей через DI

### ParticleViewModel
**Центральный компонент бизнес-логики**

**Основные обязанности:**
- Управление состоянием частиц (загрузка, генерация, симуляция)
- Обработка конфигурации (пресеты качества: Draft/Standard/High/Ultra)
- Управление жизненным циклом ParticleSystem
- Обработка low-memory ситуаций
- Мониторинг прогресса генерации

**Ключевые методы:**

```swift
// Жизненный цикл системы
@MainActor func createSystem(in view: RenderView) async -> Bool
@MainActor func resetParticleSystem()
@MainActor func toggleSimulation()
@MainActor func startLightningStorm()
@MainActor func handleWillResignActive()
@MainActor func handleDidBecomeActive()
@MainActor func initializeWithFastPreview()
@MainActor func startSimulation()
@MainActor func pauseRendering()
@MainActor func resumeRendering()
@MainActor func handleLowMemory()
@MainActor func cleanupAllResources()

// Конфигурация отображения
@MainActor func setImageDisplayMode(_ mode: ImageDisplayMode)

// UI
@MainActor func makeRenderView(frame: CGRect) -> RenderView
@MainActor func updateRenderViewLayout(frame: CGRect, scale: CGFloat)
```

**Примечание:** `toggleSimulation()` в текущей реализации запускает сбор HQ‑изображения
через `collectHighQualityImage()` при условии, что не идет генерация HQ‑частиц.

**Управление памятью:**
- Наблюдение за `UIApplication.didReceiveMemoryWarningNotification`
- Автоматическая очистка ресурсов при низкой памяти
- Очистка временных файлов кэша

### ViewController
**Презентационный слой**

**Функциональность:**
- Отображение render view для рендеринга частиц
- Обработка пользовательского ввода
- Отображение прогресса генерации
- Управление UI состоянием

**Жесты и действия (iOS ViewController):**
- Одинарный тап: вызывает `toggleSimulation()` и запускает сбор HQ‑изображения
- Двойной тап: `pauseRendering()` + `resetParticleSystem()` и перезапуск
- Тройной тап: `startLightningStorm()` и запуск рендера

**Системные события:**
- `UIApplication.didReceiveMemoryWarningNotification` → `handleLowMemory()`

## Взаимодействие с Engine

```
Assembly (MVVM)
├── ParticleViewModel → ParticleSystemFactory
├── ViewController → Render View
└── Dependency Injection → Logger, ImageLoader
```

## Зависимости

**Внешние сервисы:**
- `LoggerProtocol` - логирование операций
- `ImageLoaderProtocol` - загрузка изображений

**Внутренние компоненты:**
- `ParticleSystemController` (`ParticleSystemControlling`) - фасад/координатор системы частиц
- `ParticleGenerationConfig` - конфигурация генерации
- Render view - Metal view для рендеринга

## Жизненный цикл

1. **Инициализация**: Создание ViewModel с зависимостями
2. **Сборка**: Assembly создает ViewController с ViewModel
3. **Конфигурация**: Применение настроек качества
4. **Создание системы**: Инициализация ParticleSystem в render view
5. **Симуляция**: Запуск и управление анимацией
6. **Очистка**: Ресурсы освобождаются при деинициализации

## Потокобезопасность

- Все публичные методы помечены `@MainActor`
- Асинхронные операции используют `Task` и `MainActor.run`
- Зависимости разрешаются потокобезопасно через DI контейнер

## Использование

```swift
// Базовое использование (ViewController сам создает RenderView и запускает createSystem)
let viewController = ParticleAssembly.assemble(withDI: AppContainer.shared)

// Дальше: показать viewController или использовать его в window/root
// Внутри ViewController:
// - makeRenderView(frame:)
// - createSystem(in:)
// - обработка жестов и вызовов startLightningStorm / toggleSimulation
```

## Тестирование

ViewModel поддерживает модульное тестирование:
- Зависимости инжектируются через DI
- Публичные методы доступны для тестирования
- Диагностические методы для проверки состояния
