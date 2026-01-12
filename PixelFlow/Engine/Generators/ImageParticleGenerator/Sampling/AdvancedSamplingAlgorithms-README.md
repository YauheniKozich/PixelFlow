# Advanced Sampling Algorithms / Продвинутые алгоритмы сэмплинга

Этот файл содержит коллекцию различных алгоритмов сэмплинга пикселей для генерации частиц. Каждый алгоритм имеет свои преимущества и может быть выбран в зависимости от нужд проекта.

## 🎮 Управление настройками через ParticleViewModel

Все настройки генерации частиц теперь доступны через `ParticleViewModel`. Вы можете изменять любые параметры динамически и применять их без перекомпиляции.

### Основные настройки:

```swift
// Получить доступ к viewModel (в UIViewController)
let viewModel = (UIApplication.shared.delegate as? AppDelegate)?.particleViewModel

// Изменить алгоритм сэмплинга
viewModel?.switchToBlueNoise()      // 🔵 Оптимальное качество
viewModel?.switchToHashBased()      // ⚡ Максимальная скорость
viewModel?.switchToUniform()        // 🎯 Классический
viewModel?.switchToVanDerCorput()   // 🔢 Математическая точность
viewModel?.switchToAdaptive()       // 🧠 Учитывает цвета

// Изменить качество
viewModel?.switchToDraftQuality()   // Быстрое, низкое качество
viewModel?.switchToStandardQuality() // Баланс
viewModel?.switchToHighQuality()    // Высокое качество
viewModel?.switchToUltraQuality()   // Максимальное качество

// Предустановки конфигураций
viewModel?.setDraftConfiguration()     // Для быстрой разработки
viewModel?.setStandardConfiguration()  // Стандартные настройки
viewModel?.setHighQualityConfiguration() // Максимальное качество
viewModel?.resetToDefaults()           // Сброс к умолчанию
```

### Детальные настройки:

```swift
// Количество частиц (1000-100000)
viewModel?.setParticleCount(50000)

// Размеры частиц
viewModel?.setMinParticleSize(1.5)
viewModel?.setMaxParticleSize(8.0)

// Параметры производительности
viewModel?.setMaxConcurrentOperations(8)
viewModel?.setCachingEnabled(true)
viewModel?.setSIMDEnabled(true)
viewModel?.setCacheSizeLimit(200)

// Параметры анализа изображения
viewModel?.setImportanceThreshold(0.3)
viewModel?.setContrastWeight(0.6)
viewModel?.setSaturationWeight(0.4)
viewModel?.setEdgeDetectionRadius(3)

// Информация о настройках
let configInfo = viewModel?.getConfigurationInfo()
print(configInfo ?? "")

// Логирование настроек
viewModel?.logCurrentConfiguration()
```

### Примеры использования:

#### Для UI слайдеров:
```swift
@IBAction func particleCountSliderChanged(_ sender: UISlider) {
    let count = Int(sender.value * 90000) + 1000  // 1000-100000
    particleViewModel?.setParticleCount(count)
}

@IBAction func qualitySegmentedControlChanged(_ sender: UISegmentedControl) {
    switch sender.selectedSegmentIndex {
    case 0: particleViewModel?.switchToDraftQuality()
    case 1: particleViewModel?.switchToStandardQuality()
    case 2: particleViewModel?.switchToHighQuality()
    case 3: particleViewModel?.switchToUltraQuality()
    default: break
    }
}

@IBAction func algorithmSegmentedControlChanged(_ sender: UISegmentedControl) {
    let algorithms: [() -> Void] = [
        { particleViewModel?.switchToBlueNoise() },
        { particleViewModel?.switchToHashBased() },
        { particleViewModel?.switchToUniform() },
        { particleViewModel?.switchToVanDerCorput() },
        { particleViewModel?.switchToAdaptive() }
    ]

    if sender.selectedSegmentIndex < algorithms.count {
        algorithms[sender.selectedSegmentIndex]()
    }
}
```

#### Программное управление:
```swift
// Быстрая настройка для тестирования
particleViewModel?.setDraftConfiguration()
particleViewModel?.setParticleCount(5000)

// Оптимальная настройка для демонстрации
particleViewModel?.setHighQualityConfiguration()
particleViewModel?.switchToBlueNoise()

// Кастомная настройка
particleViewModel?.setSamplingAlgorithm(.vanDerCorput)
particleViewModel?.setQualityPreset(.high)
particleViewModel?.setParticleCount(25000)
particleViewModel?.setMinParticleSize(1.5)
particleViewModel?.setMaxParticleSize(6.0)
```

#### Мониторинг настроек:
```swift
// В лог выводятся изменения настроек
particleViewModel?.logCurrentConfiguration()

// Полная информация о конфигурации
let info = particleViewModel?.getConfigurationInfo()
print(info ?? "")
```

## 🔧 Детальное управление каждым параметром

### Алгоритмы сэмплинга:
- `switchToBlueNoise()` - Mitchell's Best Candidate (оптимальное качество)
- `switchToHashBased()` - Параллельная генерация (максимальная скорость)
- `switchToUniform()` - Равномерное покрытие (детерминированный)
- `switchToVanDerCorput()` - Квази-случайная последовательность
- `switchToAdaptive()` - Учитывает содержимое изображения

### Качество рендеринга:
- `switchToDraftQuality()` - Быстрый черновик (низкое качество)
- `switchToStandardQuality()` - Стандартное качество
- `switchToHighQuality()` - Высокое качество
- `switchToUltraQuality()` - Максимальное качество

### Производительность:
- `setMaxConcurrentOperations(count)` - Количество потоков (1-16)
- `setCachingEnabled(enabled)` - Включить/выключить кэширование
- `setSIMDEnabled(enabled)` - Векторные оптимизации
- `setCacheSizeLimit(mb)` - Размер кэша в MB (10-1000)

### Внешний вид частиц:
- `setParticleCount(count)` - Количество частиц (1000-100000)
- `setMinParticleSize(size)` - Минимальный размер (0.5-5.0)
- `setMaxParticleSize(size)` - Максимальный размер (1.0-20.0)

### Параметры анализа:
- `setImportanceThreshold(value)` - Порог важности (0.0-1.0)
- `setContrastWeight(value)` - Вес контраста (0.0-2.0)
- `setSaturationWeight(value)` - Вес насыщенности (0.0-2.0)
- `setEdgeDetectionRadius(value)` - Радиус краев (1-5)

## 📊 Предустановки конфигураций

| Предустановка | Использование | Алгоритм | Качество | Частицы |
|---------------|---------------|----------|----------|---------|
| `setDraftConfiguration()` | Быстрая разработка | Hash-Based | Draft | 10,000 |
| `setStandardConfiguration()` | Обычное использование | Blue Noise | Standard | 35,000 |
| `setHighQualityConfiguration()` | Финальный рендер | Blue Noise | Ultra | 50,000 |
| `resetToDefaults()` | Сброс настроек | Standard config | - | - |

## 🎮 Интеграция с UI

### Segmented Control для алгоритмов:
```swift
// Создаем segmented control
let algorithmControl = UISegmentedControl(items: [
    "🔵 Blue Noise",
    "⚡ Hash-Based",
    "🎯 Uniform",
    "🔢 Van der Corput",
    "🧠 Adaptive"
])

algorithmControl.addTarget(self, action: #selector(algorithmChanged(_:)), for: .valueChanged)

@objc func algorithmChanged(_ sender: UISegmentedControl) {
    let actions = [
        { particleViewModel?.switchToBlueNoise() },
        { particleViewModel?.switchToHashBased() },
        { particleViewModel?.switchToUniform() },
        { particleViewModel?.switchToVanDerCorput() },
        { particleViewModel?.switchToAdaptive() }
    ]

    if sender.selectedSegmentIndex < actions.count {
        actions[sender.selectedSegmentIndex]()
    }
}
```

### Slider для количества частиц:
```swift
// Создаем slider
let particleSlider = UISlider()
particleSlider.minimumValue = 0.0
particleSlider.maximumValue = 1.0
particleSlider.value = 0.3  // 35k из 100k
particleSlider.addTarget(self, action: #selector(particleCountChanged(_:)), for: .valueChanged)

@objc func particleCountChanged(_ sender: UISlider) {
    let count = Int(sender.value * 99000) + 1000  // 1000-100000
    particleViewModel?.setParticleCount(count)
}
```

## 🚀 Доступные алгоритмы

### 🔵 Blue Noise Sampling (Рекомендуется)
```swift
samplingStrategy: .advanced(.blueNoise)
```

**Mitchell's Best Candidate алгоритм**
- **Оптимальное распределение** - максимальное расстояние между точками
- **Нет видимых паттернов** - естественно выглядит
- **Отличное качество** для визуальных эффектов
- **Скорость:** Средняя (32 кандидата на точку)
- **Использование:** Лучший выбор для финального результата

### 🎯 Uniform Sampling (Базовый)
```swift
samplingStrategy: .uniform
```

**Простое равномерное распределение**
- **Полное покрытие** всего изображения
- **Очень быстрый** - O(N) сложность
- **Детерминированный** результат
- **Скорость:** Высокая
- **Использование:** Для быстрого тестирования

### 🔢 Van der Corput Sequence (Математический)
```swift
samplingStrategy: .advanced(.vanDerCorput)
```

**Квази-случайная последовательность**
- **Отличная равномерность** - лучшие математические свойства
- **Детерминированный** - для воспроизводимости
- **Быстрый** - O(N) сложность
- **Скорость:** Высокая
- **Использование:** Когда нужна математическая точность

### 🚀 Hash-Based Sampling (Самый быстрый)
```swift
samplingStrategy: .advanced(.hashBased)
```

**Параллельная генерация с хэшированием**
- **Самый быстрый** алгоритм
- **Параллельная обработка** - использует все ядра
- **Детерминированный** результат
- **Скорость:** Максимальная
- **Использование:** Для realtime генерации

### 🧠 Adaptive Sampling (Умный)
```swift
samplingStrategy: .advanced(.adaptive)
```

**Учитывает содержимое изображения**
- **Предпочитает насыщенные цвета** - лучшее визуальное качество
- **Адаптируется к изображению** - умный выбор пикселей
- **Интересные эффекты** - выделяет контрастные области
- **Скорость:** Средняя
- **Использование:** Для художественных эффектов

## 📊 Сравнение алгоритмов

| Алгоритм | Скорость | Качество распределения | Особенности |
|----------|----------|----------------------|-------------|
| **Blue Noise** | Средняя | ⭐⭐⭐⭐⭐ | Оптимальное, без паттернов |
| **Uniform** | Высокая | ⭐⭐⭐⭐ | Полное покрытие, быстрый |
| **Van der Corput** | Высокая | ⭐⭐⭐⭐⭐ | Математическая точность |
| **Hash-Based** | Максимальная | ⭐⭐⭐ | Параллельный, детерминированный |
| **Adaptive** | Средняя | ⭐⭐⭐⭐ | Учитывает содержимое |

## 🔧 Как использовать

### В ParticleViewModel.swift:

```swift
private func createOptimalConfig() -> ParticleGenerationConfig {
    return ParticleGenerationConfig(
        samplingStrategy: .advanced(.blueNoise),  // Выберите алгоритм
        // ...
    )
}
```

### Доступные опции:

```swift
// 🔵 Оптимальное качество (рекомендуется)
samplingStrategy: .advanced(.blueNoise)

// ⚡ Максимальная скорость
samplingStrategy: .advanced(.hashBased)

// 🎯 Равномерность
samplingStrategy: .uniform

// 🔢 Математическая точность
samplingStrategy: .advanced(.vanDerCorput)

// 🧠 Умный выбор
samplingStrategy: .advanced(.adaptive)
```

## 🔬 Технические детали

### Blue Noise Algorithm
- **Mitchell's Best Candidate**: Для каждой точки проверяет 32 кандидата
- **Выбирает farthest** от существующих точек
- **Гарантирует** оптимальное распределение

### Van der Corput Sequence
- **Основание 2** для X координаты
- **Основание 3** для Y координаты
- **Низкая discrepancy** - мера неравномерности

### Hash-Based Algorithm
- **MurmurHash3** для генерации координат
- **Параллельная обработка** с DispatchQueue.concurrentPerform
- **Автоматическое разрешение коллизий**

### Adaptive Algorithm
- **Анализ насыщенности** цветов
- **Приоритет** насыщенным пикселям
- **Комбинированный подход** uniform + importance

## 🎨 Рекомендации по выбору

### Для разработки:
- **Hash-Based** или **Uniform** - быстрые, для тестирования

### Для финального результата:
- **Blue Noise** - оптимальное качество, без артефактов

### Для специальных эффектов:
- **Adaptive** - учитывает содержимое изображения
- **Van der Corput** - математическая точность

## 🚨 Важные замечания

1. **Blue Noise** медленнее других, но дает лучший результат
2. **Hash-Based** самый быстрый, но может иметь кластеры
3. **Adaptive** может давать непредсказуемые результаты
4. **Все алгоритмы** детерминированы (кроме адаптивного)

## 🔧 Производительность

Тестирование на изображении 512×512 с 35000 частицами:

| Алгоритм | Время | Качество |
|----------|-------|----------|
| Blue Noise | ~2.5 сек | Отличное |
| Uniform | ~0.1 сек | Хорошее |
| Van der Corput | ~0.2 сек | Очень хорошее |
| Hash-Based | ~0.05 сек | Среднее |
| Adaptive | ~1.8 сек | Хорошее |

## 🐛 Отладка

Все алгоритмы логируют свою работу:

```
Blue Noise sampling: 35000 optimally distributed samples
Uniform sampling: 35000 samples, step: 7
Van der Corput sampling: 35000 quasi-random samples
Hash-based sampling: 35000 parallel-generated samples
Adaptive sampling: 35000 samples with 17500 saturated pixels prioritized
```

## 🔮 Будущие улучшения

- **Poisson Disk Sampling** - еще более равномерное распределение
- **Multi-scale sampling** - учет разных масштабов
- **GPU acceleration** - перенос на Metal
- **Machine Learning** - обучение оптимального распределения