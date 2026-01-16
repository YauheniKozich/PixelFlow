# Errors - Система ошибок

Единая система ошибок PixelFlow с локализованными сообщениями и категоризацией по модулям.

## Обзор

Все ошибки наследуются от `PixelFlowError` - объединенного enum с категориями:

```swift
enum PixelFlowError: LocalizedError {
    // Generator Errors
    case invalidImage
    case invalidParticleCount
    case analysisFailed(reason: String)
    // ... другие случаи
}
```

## Категории ошибок

### Generator Errors
**Ошибки генератора частиц**

```swift
// Входные данные
case invalidImage                           // Некорректное изображение
case invalidParticleCount                   // Некорректное количество частиц
case invalidImageDimensions                 // Неверные размеры изображения

// Процесс генерации
case analysisFailed(reason: String)         // Ошибка анализа
case samplingFailed(reason: String)         // Ошибка сэмплинга
case assemblyFailed(reason: String)         // Ошибка сборки частиц
case stageFailed(stage: String, error: Error) // Ошибка конкретного этапа

// Кэширование
case cacheError(reason: String)             // Ошибка кэша
case cacheCreationFailed(underlying: Error) // Не удалось создать кэш
```

### Metal Errors
**Ошибки Metal фреймворка**

```swift
case libraryCreationFailed                  // Не удалось создать Metal библиотеку
case functionNotFound(name: String)         // Функция шейдера не найдена
case bufferCreationFailed                   // Не удалось создать буферы
case pipelineCreationFailed                 // Не удалось создать pipeline
```

### Pipeline Errors
**Ошибки конвейера генерации**

```swift
// Конфигурация
case invalidConfiguration                   // Некорректная конфигурация
case pipelineInvalidConfiguration           // Неверная конфигурация pipeline

// Данные
case invalidInput                           // Некорректный ввод
case invalidContext                         // Неверный контекст
case missingImage                           // Отсутствует изображение
case missingAnalysis                        // Отсутствует анализ
case missingSamples                         // Отсутствуют сэмплы
case missingParticles                       // Отсутствуют частицы
case invalidOutput                          // Неверный вывод
case emptyResult                            // Пустой результат
```

### Operation Errors
**Ошибки асинхронных операций**

```swift
case operationCancelled                     // Операция отменена
case operationTimeout                       // Превышено время ожидания
case insufficientConcurrency                // Недостаточный параллелизм
```

### Image Loader Errors
**Ошибки загрузки изображений**

```swift
case invalidImageData                       // Неверные данные изображения
case imageLoaderNetworkError(Error)         // Ошибка сети
```

### Validation Errors
**Ошибки валидации входных данных**

```swift
case validationInvalidParticleCount(String) // Неверное количество частиц
case validationInvalidScreenSize(String)    // Неверный размер экрана
case validationInvalidImage(String)          // Неверное изображение
```

## Локализация

Все ошибки реализуют `LocalizedError`:

```swift
var errorDescription: String? {
    switch self {
    case .invalidImage:
        return "Некорректное изображение"
    case .analysisFailed(let reason):
        return "Ошибка анализа: \(reason)"
    // ...
    }
}
```

**Особенности локализации:**
- Сообщения на русском языке
- Детальные описания для диагностики
- Включают контекстную информацию (размеры, причины)

## Использование

### Бросание ошибок

```swift
// Простая ошибка
throw PixelFlowError.invalidImage

// Ошибка с контекстом
throw PixelFlowError.analysisFailed(reason: "Изображение слишком маленькое")

// Ошибка этапа
throw PixelFlowError.stageFailed(stage: "Sampling", error: underlyingError)
```

### Обработка ошибок

```swift
do {
    let particles = try await coordinator.generateParticles(...)
} catch let error as PixelFlowError {
    switch error {
    case .invalidImage:
        showAlert("Пожалуйста, выберите корректное изображение")
    case .analysisFailed(let reason):
        logger.error("Анализ не удался: \(reason)")
    default:
        showGenericError(error.localizedDescription)
    }
} catch {
    // Другие ошибки
    logger.error("Неожиданная ошибка: \(error)")
}
```

### Валидация с ошибками

```swift
func validate(config: ParticleGenerationConfig) throws {
    guard config.targetParticleCount > 0 else {
        throw PixelFlowError.validationInvalidParticleCount(
            "Количество частиц должно быть положительным числом"
        )
    }

    guard config.targetParticleCount <= 300_000 else {
        throw PixelFlowError.validationInvalidParticleCount(
            "Максимальное количество частиц: 300,000"
        )
    }
}
```

## Архитектура

### Единый enum
- Все ошибки в одном месте для consistency
- Легко расширять новыми категориями
- Упрощает обработку в UI слое

### Type aliases (для обратной совместимости)

```swift
typealias GeneratorError = PixelFlowError
typealias MetalError = PixelFlowError
typealias SamplingError = PixelFlowError
// ...
```

### LocalizedError протокол
- Стандартизированные сообщения
- Поддержка системной локализации
- Детальная диагностика

## Лучшие практики

### Когда использовать PixelFlowError

- **Пользовательские ошибки**: Когда пользователь может исправить ситуацию
- **Конфигурационные ошибки**: Неверные настройки или входные данные
- **Системные ограничения**: Недостаточно памяти, неподдерживаемые форматы

### Когда НЕ использовать

- **Программные ошибки**: Использовать `fatalError` или `assertionFailure`
- **Внутренние состояния**: Для логики, а не ошибок
- **Debug assertions**: Для development проверок

### Обработка в UI

```swift
extension UIViewController {
    func handlePixelFlowError(_ error: PixelFlowError) {
        let message = error.localizedDescription
        let alert = UIAlertController(title: "Ошибка", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        present(alert, animated: true)
    }
}
```

## Тестирование

Система ошибок поддерживает тестирование:

```swift
// Тестирование бросания ошибок
XCTAssertThrowsError(try invalidOperation()) { error in
    XCTAssertEqual(error as? PixelFlowError, .invalidImage)
}

// Тестирование сообщений
let error = PixelFlowError.invalidImage
XCTAssertEqual(error.localizedDescription, "Некорректное изображение")