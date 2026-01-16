# UI - Пользовательский интерфейс

UI слой PixelFlow, отвечающий за приложение iOS/macOS, управление жизненным циклом и интеграцию с системой.

## Архитектура

UI слой включает:
- **AppDelegate.swift** - делегат приложения
- **SceneDelegate.swift** - делегат сцены (iOS)

## AppDelegate
**Основной делегат приложения**

```swift
@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    // MARK: - UIApplicationDelegate

    func application(_ application: UIApplication,
                    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        Logger.shared.info("🚀 Приложение запущено")
        configureAppearance()
        return true
    }

    func application(_ application: UIApplication,
                    configurationForConnecting connectingSceneSession: UISceneSession,
                    options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        Logger.shared.info("Создание новой сессии сцены")
        return UISceneConfiguration(name: "Default Configuration",
                                  sessionRole: connectingSceneSession.role)
    }

    func application(_ application: UIApplication,
                    didDiscardSceneSessions sceneSessions: Set<UISceneSession>) {
        Logger.shared.info("Сессии сцены закрыты: \(sceneSessions.count)")
    }
}
```

**Обязанности:**
- **Инициализация**: Настройка внешнего вида, логирование запуска
- **Жизненный цикл**: Обработка запуска, завершения, фонового режима
- **Конфигурация сцен**: Создание конфигураций для новых сцен
- **Низкая память**: Обработка `didReceiveMemoryWarning`

### configureAppearance()
**Настройка внешнего вида приложения**

```swift
private func configureAppearance() {
    if #available(iOS 13.0, *) {
        let appearance = UINavigationBarAppearance()
        appearance.configureWithOpaqueBackground()
        appearance.backgroundColor = .black
        appearance.titleTextAttributes = [.foregroundColor: UIColor.white]

        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    } else {
        UINavigationBar.appearance().barTintColor = .black
        UINavigationBar.appearance().titleTextAttributes = [.foregroundColor: UIColor.white]
    }
}
```

## SceneDelegate
**Делегат сцены для управления окнами**

```swift
final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene,
              willConnectTo session: UISceneSession,
              options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }

        // Создание окна
        let window = UIWindow(windowScene: windowScene)
        self.window = window

        // Создание корневого ViewController через Assembly
        let rootViewController = ParticleAssembly.assemble()
        window.rootViewController = rootViewController

        window.makeKeyAndVisible()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        Logger.shared.info("Сцена отключена")
    }

    func sceneDidBecomeActive(_ scene: UIScene) {
        Logger.shared.info("Сцена стала активной")
    }

    func sceneWillResignActive(_ scene: UIScene) {
        Logger.shared.info("Сцена станет неактивной")
    }

    func sceneWillEnterForeground(_ scene: UIScene) {
        Logger.shared.info("Сцена перейдет на передний план")
    }

    func sceneDidEnterBackground(_ scene: UIScene) {
        Logger.shared.info("Сцена перешла в фон")
    }
}
```

**Обязанности:**
- **Создание окна**: Инициализация UIWindow для сцены
- **Сборка UI**: Использование ParticleAssembly для создания корневого контроллера
- **Жизненный цикл сцены**: Обработка переходов активный/неактивный, foreground/background

## ViewController
**Основной контроллер приложения**

**Структура:**
- MTKView для Metal рендеринга частиц
- ParticleViewModel для бизнес-логики
- UI элементы для управления (кнопки, слайдеры, индикаторы)

**Ключевые методы:**
```swift
override func viewDidLoad() {
    super.viewDidLoad()
    setupMetalView()
    setupUIControls()
    setupViewModel()
}

func setupMetalView() {
    let mtkView = MTKView(frame: view.bounds)
    // Конфигурация Metal view
    view.addSubview(mtkView)

    // Создание системы частиц
    Task {
        let success = await viewModel.createSystem(in: mtkView)
        if success {
            // Начать симуляцию
        }
    }
}
```

## Жизненный цикл приложения

```
App Launch → AppDelegate.didFinishLaunching → SceneDelegate.willConnectToScene
    ↓
Создание окна → Assembly.assemble() → ViewController с ParticleViewModel
    ↓
setupMetalView() → viewModel.createSystem() → ParticleSystem инициализация
    ↓
Симуляция частиц → Metal рендеринг
```

## Кроссплатформенность

UI слой поддерживает iOS и macOS:

```swift
#if os(iOS)
typealias PlatformViewController = UIViewController
typealias PlatformSceneDelegate = UIResponder & UIWindowSceneDelegate
#elseif os(macOS)
typealias PlatformViewController = NSViewController
typealias PlatformSceneDelegate = NSObject & NSApplicationDelegate
#endif
```

## Интеграция с системой

- **UIApplicationDelegate**: Обработка системных событий
- **UIWindowSceneDelegate**: Управление сценами и окнами
- **Logger**: Логирование всех UI событий
- **ParticleAssembly**: MVVM сборка компонентов

## Тестирование

UI компоненты тестируются через:
- **Unit тесты** для ViewModel
- **UI тесты** для контроллеров
- **Интеграционные тесты** для Assembly

## Производительность

- **Lazy loading**: Компоненты создаются по необходимости
- **Memory management**: Правильная очистка ресурсов
- **Main thread**: Все UI операции на главном потоке
- **Async/await**: Асинхронные операции без блокировки UI