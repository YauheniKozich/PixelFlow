# Configuration - Конфигурация системы

Гибкие настройки для управления поведением генератора частиц.

## Файлы

### Configuration.swift
**Конфигурационные структуры и перечисления**

## Основные структуры

### ParticleGenerationConfig
**Главная конфигурационная структура**

```swift
struct ParticleGenerationConfig: Codable, ParticleGeneratorConfiguration {
    // Стратегия сэмплинга
    let samplingStrategy: SamplingStrategy

    // Пресет качества
    let qualityPreset: QualityPreset

    // Настройки кэширования
    let enableCaching: Bool
    let maxConcurrentOperations: Int

    // Параметры анализа
    let importanceThreshold: Float
    let contrastWeight: Float
    let saturationWeight: Float
    let edgeDetectionRadius: Int

    // Параметры частиц
    let minParticleSize: Float
    let maxParticleSize: Float

    // Оптимизации
    let useSIMD: Bool
    let cacheSizeLimit: Int
}
```

### SamplingStrategy
**Стратегии выбора пикселей**

```swift
enum SamplingStrategy: Codable {
    case uniform        // Равномерный сэмплинг
    case importance     // По важности пикселей
    case adaptive       // Адаптивная плотность
    case hybrid         // Комбинированный подход
}
```

### QualityPreset
**Пресеты качества генерации**

```swift
enum QualityPreset: Codable {
    case draft     // Быстрый черновик (низкое качество)
    case standard  // Стандартное качество
    case high      // Высокое качество
    case ultra     // Максимальное качество
}
```

## Предустановленные конфигурации

### `ParticleGenerationConfig.default`
Стандартная конфигурация для большинства случаев:
- Strategy: `importance`
- Quality: `standard`
- Caching: `true`
- SIMD: `true`

### `ParticleGenerationConfig.draft`
Быстрая конфигурация для прототипов:
- Strategy: `uniform`
- Quality: `draft`
- Caching: `false`
- SIMD: `false`

### `ParticleGenerationConfig.highQuality`
Высококачественная конфигурация:
- Strategy: `hybrid`
- Quality: `ultra`
- Caching: `true`
- SIMD: `true`

## Параметры качества

### Importance Threshold
Порог важности пикселей (0.0 - 1.0):
- Низкие значения: больше пикселей
- Высокие значения: только самые важные

### Contrast Weight
Вес контраста в оценке важности (0.0 - 1.0):
- Высокий вес: предпочтение контрастным областям

### Saturation Weight
Вес насыщенности в оценке важности (0.0 - 1.0):
- Высокий вес: предпочтение насыщенным цветам

### Edge Detection Radius
Радиус анализа соседей для контраста (1 - 5):
- Больший радиус: более плавная оценка

## Производительность

### Max Concurrent Operations
Максимальное количество одновременных операций:
- Автоматически = количеству ядер процессора

### Use SIMD
Использование SIMD оптимизаций:
- `true`: максимальная производительность
- `false`: совместимость с старым оборудованием

### Cache Size Limit
Лимит размера кэша в МБ:
- `0`: отключить кэширование
- `100+`: рекомендуемый размер

## Применение

### Базовая настройка
```swift
let config = ParticleGenerationConfig.default
let generator = try ImageParticleGenerator(image: image, particleCount: 1000, config: config)
```

### Кастомная конфигурация
```swift
var config = ParticleGenerationConfig.default
config.samplingStrategy = .hybrid
config.qualityPreset = .high
config.enableCaching = true
config.maxParticleSize = 15.0
```

### Производительность vs Качество
```swift
// Максимальная производительность
let fastConfig = ParticleGenerationConfig.draft

// Максимальное качество
let qualityConfig = ParticleGenerationConfig.highQuality
```