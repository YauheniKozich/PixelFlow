# API Integration Guide - Руководство по интеграции PixelFlow

Полное руководство по интеграции PixelFlow в ваше iOS/macOS приложение для создания эффектов частиц из изображений.

## Быстрый старт

### Минимальная интеграция

```swift
import PixelFlow

// 1. Создать ViewModel
let viewModel = ParticleViewModel()

// 2. Создать ViewController
let particleVC = ParticleAssembly.assemble()

// 3. Добавить в навигацию
navigationController?.pushViewController(particleVC, animated: true)
```

**Результат:** Полнофункциональное приложение с генерацией частиц из встроенного изображения.

## Детальная интеграция

### Шаг 1: Подготовка проекта

#### Добавление зависимостей
```swift
// В Package.swift
dependencies: [
    .package(url: "https://github.com/yourorg/PixelFlow.git", from: "1.0.0")
]

// В target dependencies
.product(name: "PixelFlow", package: "PixelFlow")
```

#### Конфигурация Info.plist
```xml
<key>NSPhotoLibraryUsageDescription</key>
<string>Для загрузки изображений и создания эффектов частиц</string>

<key>NSCameraUsageDescription</key>
<string>Для съемки фото и создания эффектов частиц</string>

<key>UIRequiredDeviceCapabilities</key>
<array>
    <string>metal</string>
</array>
```

### Шаг 2: Базовая настройка

#### Инициализация DI контейнера
```swift
// В AppDelegate или раннем этапе
func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    // Регистрация зависимостей
    register(Logger.shared, for: LoggerProtocol.self)
    register(ImageLoader(), for: ImageLoaderProtocol.self)

    return true
}
```

#### Создание компонентов
```swift
class MyViewController: UIViewController {
    private var particleViewModel: ParticleViewModel?
    private var particleViewController: UIViewController?

    override func viewDidLoad() {
        super.viewDidLoad()
        setupParticleSystem()
    }

    private func setupParticleSystem() {
        // Создание ViewModel
        particleViewModel = ParticleViewModel()

        // Создание Particle ViewController через Assembly
        particleViewController = ParticleAssembly.assemble()

        // Добавление на экран
        addChild(particleViewController!)
        view.addSubview(particleViewController!.view)
        particleViewController!.view.frame = view.bounds
        particleViewController!.didMove(toParent: self)
    }
}
```

### Шаг 3: Конфигурация системы

#### Пресеты качества
```swift
// Draft - быстрый превью (низкое качество)
particleViewModel?.applyDraftPreset()

// Standard - баланс качества и производительности
particleViewModel?.applyStandardPreset()

// High - высокое качество
particleViewModel?.applyHighPreset()

// Ultra - максимальное качество
particleViewModel?.applyUltraPreset()
```

#### Кастомная конфигурация
```swift
var config = ParticleGenerationConfig.standard
config.targetParticleCount = 50000
config.samplingStrategy = .importance
config.enableCaching = true
config.useSIMD = true
config.maxConcurrentOperations = 4

particleViewModel?.apply(config)
```

### Шаг 4: Управление симуляцией

#### Базовое управление
```swift
// Запуск симуляции
particleViewModel?.toggleSimulation()

// Специальные эффекты
particleViewModel?.startLightningStorm()

// Остановка и очистка
particleViewModel?.resetParticleSystem()
```

#### Продвинутые возможности
```swift
// Мониторинг состояния
if let viewModel = particleViewModel {
    let status = viewModel.configurationInfo()
    print("Particle System Status: \(status)")
}

// Диагностика
viewModel.logCurrentConfiguration()
```

## Работа с изображениями

### Использование встроенных изображений
```swift
// Система автоматически использует steve.png из ассетов
// Ничего дополнительно не требуется
```

### Загрузка пользовательских изображений
```swift
class ImagePickerController: UIViewController, UIImagePickerControllerDelegate {
    private var particleViewModel: ParticleViewModel?

    func pickImageFromGallery() {
        let picker = UIImagePickerController()
        picker.delegate = self
        picker.sourceType = .photoLibrary
        present(picker, animated: true)
    }

    func imagePickerController(_ picker: UIImagePickerController,
                              didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey : Any]) {
        if let image = info[.originalImage] as? UIImage,
           let cgImage = image.cgImage {
            // Создание новой системы с выбранным изображением
            createParticleSystem(with: cgImage)
        }
    }

    private func createParticleSystem(with image: CGImage) {
        // Реализация создания новой системы частиц
        // (требует доступа к внутренним компонентам)
    }
}
```

## Обработка ошибок

### Базовая обработка
```swift
Task {
    do {
        let success = try await particleViewModel?.createSystem(in: mtkView)
        if !success {
            showErrorAlert("Не удалось создать систему частиц")
        }
    } catch let error as PixelFlowError {
        handlePixelFlowError(error)
    } catch {
        showGenericError("Неизвестная ошибка: \(error.localizedDescription)")
    }
}

private func handlePixelFlowError(_ error: PixelFlowError) {
    let message: String
    switch error {
    case .invalidImage:
        message = "Выбрано некорректное изображение"
    case .analysisFailed(let reason):
        message = "Ошибка анализа изображения: \(reason)"
    case .metalError:
        message = "Ошибка графики. Проверьте устройство."
    default:
        message = error.localizedDescription
    }
    showErrorAlert(message)
}
```

## Производительность и оптимизация

### Рекомендации по количеству частиц
```swift
func optimalParticleCount(for device: MTLDevice, imageSize: CGSize) -> Int {
    let pixelCount = Int(imageSize.width * imageSize.height)

    // iPhone SE / iPad mini
    if device.name.contains("A12") || device.name.contains("A13") {
        return min(pixelCount / 400, 50000)
    }

    // iPhone 12+ / iPad Pro
    if device.name.contains("A14") || device.name.contains("M1") {
        return min(pixelCount / 200, 150000)
    }

    // Mac / высокопроизводительные устройства
    return min(pixelCount / 100, 300000)
}
```

### Управление памятью
```swift
// Наблюдение за memory warnings
NotificationCenter.default.addObserver(
    self,
    selector: #selector(handleMemoryWarning),
    name: UIApplication.didReceiveMemoryWarningNotification,
    object: nil
)

@objc private func handleMemoryWarning() {
    // Очистка кэша и ресурсов
    particleViewModel?.cleanupAllResources()

    // Уменьшение количества частиц
    var config = ParticleGenerationConfig.draft
    config.targetParticleCount = 10000
    particleViewModel?.apply(config)
}
```

## Продвинутые возможности

### Кастомные стратегии генерации
```swift
// Создание кастомной конфигурации
let config = ParticleGenerationConfig(
    samplingStrategy: .hybrid,
    qualityPreset: .custom(
        minParticleSize: 1.5,
        maxParticleSize: 4.0,
        contrastWeight: 0.8,
        saturationWeight: 0.6
    ),
    enableCaching: true,
    useSIMD: true
)

particleViewModel?.apply(config)
```

### Интеграция с другими Metal приложениями
```swift
// Получение Metal device и command queue
if let particleVC = particleViewController as? YourParticleVC,
   let adapter = particleVC.particleSystemAdapter {
    let device = adapter.device
    let commandQueue = adapter.commandQueue

    // Использование в вашем Metal коде
    // ...
}
```

## Тестирование интеграции

### Unit тесты
```swift
class PixelFlowIntegrationTests: XCTestCase {
    var viewModel: ParticleViewModel!

    override func setUp() {
        super.setUp()
        viewModel = ParticleViewModel()
    }

    func testConfigurationApplication() {
        // Given
        let config = ParticleGenerationConfig.draft

        // When
        viewModel.apply(config)

        // Then
        XCTAssertEqual(viewModel.currentConfig.qualityPreset, .draft)
    }

    func testMemoryCleanup() {
        // Given
        let expectation = expectation(description: "Cleanup completed")

        // When
        viewModel.cleanupAllResources()

        // Then
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
            // Verify cleanup
            expectation.fulfill()
        }

        wait(for: [expectation], timeout: 1.0)
    }
}
```

### UI тесты
```swift
class PixelFlowUITests: XCTestCase {
    func testParticleSystemCreation() {
        let app = XCUIApplication()

        // Запуск приложения
        app.launch()

        // Проверка создания частиц
        let particleView = app.otherElements["ParticleView"]
        XCTAssertTrue(particleView.exists)

        // Проверка элементов управления
        let playButton = app.buttons["PlayButton"]
        XCTAssertTrue(playButton.exists)
    }
}
```

## Troubleshooting

### Распространенные проблемы

#### "Не удалось создать систему частиц"
- **Причина:** Недостаточно памяти или неподдерживаемое устройство
- **Решение:** Уменьшить `targetParticleCount`, проверить Metal поддержку

#### "Частицы не отображаются"
- **Причина:** Проблемы с MTKView или Metal pipeline
- **Решение:** Проверить Metal device, обновить драйверы

#### "Низкая производительность"
- **Причина:** Слишком много частиц для устройства
- **Решение:** Использовать `ParticleGenerationConfig.draft`, уменьшить количество

#### "Ошибки кэширования"
- **Причина:** Недостаточно места на диске
- **Решение:** Очистить кэш, проверить доступ к временной директории

### Отладочная информация
```swift
// Получение диагностики
if let info = particleViewModel?.configurationInfo() {
    print("=== Диагностика системы ===")
    print(info)
    print("==========================")
}

// Логирование всех операций
Logger.shared.logLevel = .debug
```

## Миграция с предыдущих версий

### Из v1.x в v2.x
```swift
// Старый API
let particleSystem = ParticleSystem()
particleSystem.configure(with: image, particleCount: 10000)

// Новый API
let viewModel = ParticleViewModel()
viewModel.apply(ParticleGenerationConfig.standard)
// Использовать через Assembly паттерн
```

## Поддержка и ресурсы

### Документация
- [Engine Documentation](PixelFlow/Engine/engine.md)
- [API Reference](api-reference.md)
- [Shader Guide](PixelFlow/Engine/Shaders/shaders.md)

### Примеры
- [Basic Integration](Examples/BasicIntegration/)
- [Custom Configuration](Examples/CustomConfig/)
- [Performance Optimization](Examples/Performance/)

### Сообщество
- GitHub Issues для баг репортов
- Discussions для вопросов
- Discord/Slack для real-time помощи