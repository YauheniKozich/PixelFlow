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
// Конфигурация
@MainActor func apply(_ config: ParticleGenerationConfig)
@MainActor func applyDraftPreset()
@MainActor func applyStandardPreset()
@MainActor func applyHighPreset()
@MainActor func applyUltraPreset()

// Жизненный цикл системы
@MainActor func createSystem(in view: UIView) async -> Bool
@MainActor func resetParticleSystem()
@MainActor func toggleSimulation()
@MainActor func startLightningStorm()

// Диагностика
@MainActor func configurationInfo() -> String
@MainActor func logCurrentConfiguration()
```

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
- `ParticleSystemAdapter` - адаптер для совместимости
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
// Базовое использование
let viewController = ParticleAssembly.assemble()
let config = ParticleGenerationConfig.standard
await viewController.viewModel?.apply(config)

// Расширенное использование
if let viewModel = viewController.viewModel {
    let success = await viewModel.createSystem(in: renderView)
    if success {
        viewModel.startLightningStorm()
    }
}
```

## Тестирование

ViewModel поддерживает модульное тестирование:
- Зависимости инжектируются через DI
- Публичные методы доступны для тестирования
- Диагностические методы для проверки состояния
