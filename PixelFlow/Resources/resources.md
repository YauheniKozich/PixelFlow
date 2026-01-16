# Resources - Ресурсы и ассеты

Система ресурсов PixelFlow, включая ассеты, локализацию и управление ресурсами приложения.

## Структура ресурсов

```
Resources/
├── Assets.xcassets/       # Ассеты приложения
│   ├── Contents.json
│   ├── AccentColor.colorset/
│   ├── AppIcon.appiconset/
│   └── steve.imageset/
├── Base.lproj/           # Локализация
│   └── LaunchScreen.storyboard
└── README.md             # Документация ресурсов
```

## Assets.xcassets

### AppIcon
**Иконка приложения**

**Форматы:**
- iOS: 20pt, 29pt, 40pt, 60pt (1x, 2x, 3x)
- iPad: 20pt, 29pt, 40pt, 76pt, 83.5pt
- Mac: 16pt, 32pt, 128pt, 256pt, 512pt

**Требования к иконке:**
- Формат: PNG
- Фон: Прозрачный или сплошной
- Стиль: Современный, recognizable

### AccentColor
**Акцентный цвет приложения**

```xml
<!-- Contents.json -->
{
  "colors" : [
    {
      "color" : {
        "color-space" : "srgb",
        "components" : {
          "alpha" : "1.000",
          "blue" : "0.373",
          "green" : "0.424",
          "red" : "0.478"
        }
      },
      "idiom" : "universal"
    }
  ],
  "info" : {
    "author" : "xcode",
    "version" : 1
  }
}
```

**Использование:**
- UI элементы (кнопки, выделение)
- Акцент в темной теме
- Брендинг элементов

### steve.imageset
**Тестовое изображение для демонстрации**

**Свойства:**
- Размер: 512x512px
- Формат: PNG
- Назначение: Fallback изображение для генерации частиц

**Использование в коде:**
```swift
// ImageLoader.swift
func loadImageWithFallback() -> CGImage? {
    let possibleNames = ["steve", "test", "image"]
    for name in possibleNames {
        if let ui = UIImage(named: name) {
            return ui.cgImage
        }
    }
    return createTestImage()
}
```

## Base.lproj - Локализация

### LaunchScreen.storyboard
**Экран запуска приложения**

**Элементы:**
- Фон: Градиент от синего к фиолетовому
- Логотип: PixelFlow branding
- Анимация: Простая загрузка

**Конфигурация:**
- Размеры: Поддержка всех устройств
- Ориентации: Portrait и Landscape
- Темы: Светлая/темная тема

## Управление ресурсами

### ImageLoader
**Сервис загрузки изображений**

**Приоритеты загрузки:**
1. **Asset catalog**: `steve.png` из Assets.xcassets
2. **Bundle resources**: Другие изображения в bundle
3. **Generated fallback**: Программная генерация тестового изображения

**Тестовое изображение:**
```swift
private func createTestImage() -> CGImage? {
    let size = CGSize(width: 512, height: 512)
    let renderer = UIGraphicsImageRenderer(size: size)

    let ui = renderer.image { ctx in
        // Градиентный фон
        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor] as CFArray,
            locations: [0, 1]
        )

        if let gradient = gradient {
            ctx.cgContext.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: []
            )
        }

        // Геометрические фигуры для визуального интереса
        UIColor.white.setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 100, dy: 100)).fill()

        UIColor.black.setFill()
        UIBezierPath(ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 200, dy: 200)).fill()
    }

    return ui.cgImage
}
```

## Оптимизация ресурсов

### Размеры изображений
- **App Icons**: Автоматическая генерация всех размеров
- **Тестовые изображения**: 512x512px для баланса качества/размера
- **Launch Screen**: Векторные элементы для масштабируемости

### Форматы
- **PNG**: Для иконок и тестовых изображений (прозрачность)
- **PDF**: Для векторных элементов (если применимо)
- **HEIC/HEIF**: Для фотографий (меньший размер)

### Управление памятью
- **Lazy loading**: Загрузка по требованию
- **Caching**: Автоматическое кэширование UIKit
- **Cleanup**: Очистка при low memory warnings

## Добавление новых ресурсов

### Новое изображение
1. Добавить в `Assets.xcassets`
2. Создать новый image set
3. Импортировать изображения для разных масштабов (1x, 2x, 3x)
4. Обновить `ImageLoader` если нужно

### Новая локализация
1. Добавить папку `[language].lproj`
2. Скопировать `LaunchScreen.storyboard`
3. Локализовать текстовые элементы
4. Обновить Info.plist

## Контроль качества

### Проверка ресурсов
- **Xcode validation**: Автоматическая проверка asset catalog
- **Manual testing**: Проверка на всех устройствах
- **Performance**: Мониторинг размера bundle
- **Accessibility**: Проверка контрастности цветов

### Bundle size
- **Цель**: < 50MB для основных ассетов
- **Оптимизация**: Сжатие изображений без потери качества
- **Анализ**: Использование Xcode Debug > View UI Hierarchy

## Использование в разработке

### Доступ к ресурсам
```swift
// Изображения
let image = UIImage(named: "steve")

// Цвета
let accentColor = UIColor(named: "AccentColor")

// Локализованные строки
let title = NSLocalizedString("app.title", comment: "Application title")
```

### Тестирование ресурсов
```swift
func testImageLoading() {
    let loader = ImageLoader()
    let image = loader.loadImageWithFallback()
    XCTAssertNotNil(image, "Should load fallback image")
    XCTAssertEqual(image?.width, 512, "Width should be 512")
    XCTAssertEqual(image?.height, 512, "Height should be 512")
}
```

## Будущие улучшения

- **Dynamic assets**: Загрузка ресурсов из сети
- **Theming**: Множественные темы оформления
- **Internationalization**: Полная локализация интерфейса
- **Accessibility**: VoiceOver поддержка и динамические размеры