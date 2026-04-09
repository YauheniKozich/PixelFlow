# Assembly - MVVM слой сборки

MVVM архитектурный слой PixelFlow, отвечающий за сборку компонентов, управление жизненным циклом и связь между UI и Engine на текущем iOS target.

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

    @MainActor static func assemble(withDI container: DIContainer) -> UIViewController {
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

        let viewController = ViewController(viewModel: viewModel)

        return viewController
    }

    static func makeSceneDelegate() -> UIWindowSceneDelegate {
        return SceneDelegate()
    }
}
```

**Особенности:**
- Текущий target: iOS
- Упрощенная сборка через статические методы
- Автоматическое разрешение зависимостей через DI

### ParticleViewModel
**Центральный компонент бизнес-логики**

**Основные обязанности:**
- Управление состоянием частиц
- Обработка конфигурации качества
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
- Отображение render view
- Обработка пользовательского ввода
- Отображение прогресса
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

## Потокобезопасность

- Все публичные методы помечены `@MainActor`
- Асинхронные операции используют `Task` и `MainActor.run`
- Зависимости разрешаются потокобезопасно через DI контейнер

## Тестирование

ViewModel поддерживает модульное тестирование:
- Зависимости инжектируются через DI
- Публичные методы доступны для тестирования
- Диагностические методы для проверки состояния
