# ImageParticleGenerator - УМНЫЙ ГЕНЕРАТОР ЧАСТИЦ

Модульная архитектура для интеллектуальной генерации частиц из изображений с поддержкой различных стратегий и кэширования.

## 🎯 ОБЗОР

`ImageParticleGenerator` преобразует изображения в массивы частиц с учетом визуальной важности пикселей. Использует конвейерную архитектуру с анализом, сэмплингом, сборкой и кэшированием для создания оптимального распределения частиц.

## 📁 СТРУКТУРА

```
Engine/Generators/ImageParticleGenerator/
├── Core/
│   ├── GenerationPipeline.swift         # 🎯 Конвейер генерации частиц
│   ├── GenerationContext.swift          # 📊 Контекст выполнения
│   ├── GenerationCoordinator.swift      # 🎨 Координатор процессов
│   ├── Protocols.swift                  # 🔧 Протоколы компонентов
│   └── ImageParticleGeneratorToParticleSystemAdapter.swift # 🔗 Адаптер для ParticleSystem
├── Analysis/
│   ├── ImageAnalysis.swift              # 📊 Основной анализ изображений
│   └── ImageAnalyzer.swift              # 🔍 Анализатор с SIMD оптимизациями
├── Sampling/
│   ├── PixelSampler.swift               # 🎯 Основной сэмплер пикселей
│   ├── SamplingParameters.swift         # ⚙️ Параметры сэмплинга
│   ├── Models/
│   │   ├── Sample.swift                 # 📐 Структура сэмпла
│   │   └── SamplingParams.swift         # 🔧 Параметры стратегий
│   ├── Strategies/
│   │   ├── ImportanceSamplingStrategy.swift # 🏆 Сэмплинг по важности
│   │   ├── AdaptiveSamplingStrategy.swift   # 📈 Адаптивный сэмплинг
│   │   ├── HybridSamplingStrategy.swift     # 🔄 Гибридный сэмплинг
│   │   └── Advanced/
│   │       └── AdvancedPixelSampler.swift   # 🚀 Продвинутый сэмплер
│   └── Helpers/
│       ├── PixelSampler.c               # ⚡ C функции для производительности
│       └── ArtifactPreventionHelper.swift # 🛡️ Предотвращение артефактов
├── Assembly/
│   ├── ParticleAssembler.swift          # 🏗️ Сборка частиц
│   ├── ProtocolParticleGenerators.swift # 🔧 Протоколы генераторов
│   ├── Supporting.swift                 # 🛠️ Вспомогательные функции
│   └── ParticleAssembly.swift           # 🔗 Ассембли для MVVM
├── Strategies/
│   ├── SequentialStrategy.swift         # 🔄 Последовательная генерация
│   ├── ParallelStrategy.swift           # ⚡ Параллельная генерация
│   └── AdaptiveStrategy.swift           # 📊 Адаптивная генерация
├── Configuration/
│   ├── Configuration.swift              # ⚙️ Основные настройки
│   ├── CacheManager.swift               # 💾 Управление кэшем
│   └── OperationManager.swift           # 🎯 Управление операциями
├── Caching/
│   ├── PixelCache.swift                 # 💾 Кэширование пикселей
│   └── PixelCacheHelper.swift           # 🛠️ Вспомогательные функции кэша
└── Errors/                              # ❌ Обработка ошибок
```

## 🧠 ИНТЕЛЛЕКТ ГЕНЕРАЦИИ

### 1. 📊 АНАЛИЗ ИЗОБРАЖЕНИЯ (`ImageAnalysis.swift` + `ImageAnalyzer.swift`)
- **Цветовые метрики**: средний цвет, контраст, яркость с SIMD оптимизациями
- **Статистика**: плотность пикселей, сложность, доминирующие цвета
- **Оптимизация**: данные для умного сэмплинга с кэшированием промежуточных результатов

### 2. 🎯 УМНЫЙ СЭМПЛИНГ (`PixelSampler.swift` + стратегии)
- **Важность пикселей**: контраст, насыщенность, уникальность
- **Множественные стратегии**: Importance, Adaptive, Hybrid
- **Взвешенный выбор**: вероятностный сэмплинг по важности
- **Адаптивная плотность**: больше частиц в детализированных областях

### 3. 🏗️ СБОРКА ЧАСТИЦ (`ParticleAssembler.swift`)
- **Target позиции**: соответствуют сэмплам пикселей
- **Цвета**: наследуют цвета пикселей в формате SIMD4<Float>
- **Масштабирование**: адаптация под размер экрана устройства
- **Протоколы**: гибкая архитектура с поддержкой разных генераторов

## 🎨 АЛГОРИТМ ВАЖНОСТИ ПИКСЕЛЕЙ

```swift
// Алгоритм важности пикселей (PixelSampling.swift)
importance = (localContrast × 0.4) + (saturation × 0.3) + (minDistanceToDominant × 0.3)
```

- **Локальный контраст** (40%): разница с соседними пикселями (3x3 область)
- **Насыщенность** (30%): отклонение от серого цвета
- **Расстояние до доминирующих** (30%): уникальность цвета среди основных (чем дальше, тем уникальнее)

## 🔄 ПРОЦЕСС ГЕНЕРАЦИИ

1. **Анализ** → Изображение → `ImageAnalysis` + `ImageAnalyzer`
2. **Сэмплинг** → Важные сэмплы → `PixelSampler` с выбранной стратегией
3. **Сборка** → Частицы → `ParticleAssembler`
4. **Кэширование** → Сохранение результатов → `CacheManager`

## 📈 СТАТИСТИКА

При генерации выводится подробная статистика:
```
[sampleImage] 📊 Importance stats:
  - Average: 0.234
  - Max: 0.891
  - Min: 0.012
  - Range: 0.879
[sampleImage] ✅ Final samples: 10,000 (from 45,230 candidates)
```

## 🎯 ПРЕИМУЩЕСТВА

- ✅ **Умное распределение**: частицы там, где важнее с множественными стратегиями
- ✅ **Качество сборки**: края и детали собираются первыми с SIMD оптимизациями
- ✅ **Производительность**: оптимизированный алгоритм с Metal и Accelerate
- ✅ **Масштабируемость**: работает с любыми размерами изображений
- ✅ **Модульность**: легко модифицировать отдельные компоненты
- ✅ **Стратегии**: Sequential, Parallel, Adaptive генерация
- ✅ **Кэширование**: Автоматическое сохранение результатов
- ✅ **Прогресс**: Отслеживание этапов с callback'ами
- ✅ **Отмена**: Возможность прерывания процесса

## 🔧 ИСПОЛЬЗОВАНИЕ

```swift
let coordinator = GenerationCoordinatorFactory.makeCoordinator()
let config = ParticleGenerationConfig(targetParticleCount: 10000, qualityPreset: .high)
let particles = try await coordinator.generateParticles(
    from: image,
    config: config,
    screenSize: view.bounds.size
) { progress, stage in
    print("Progress: \(progress), Stage: \(stage)")
}
// Готово! 10,000 умно распределенных частиц
```

---

**Результат**: Частицы собираются в изображение с максимальным качеством и реализмом! 🎨✨
