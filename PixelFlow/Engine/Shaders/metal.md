# Metal Features

Обзор использования Metal в проекте PixelFlow для визуализации частиц.

## Обзор

PixelFlow использует Metal - графический и вычислительный API от Apple - для реализации системы частиц в реальном времени.

## Архитектура Metal в PixelFlow

### Основные компоненты

#### MetalRenderer
Главный компонент рендеринга, отвечающий за:
- Настройку Metal pipelines (compute и render)
- Управление буферами и текстурами
- Координацию между CPU и GPU
- Обработку кадров в реальном времени

#### Compute Pipeline
Используется для симуляции физики частиц:
- **updateParticles** - функция обновления состояния частиц
- Параллельная обработка тысяч частиц одновременно
- SIMD оптимизации для векторных вычислений

#### Render Pipeline
Отвечает за визуализацию частиц:
- **vertexParticle** - вершинный шейдер для трансформации частиц
- **fragmentParticle** - фрагментный шейдер для окраски пикселей
- **fragmentParticlePerformance** - упрощенный fragment path для `RenderQuality.performance` и `QualityPreset.draft`
- Поддержка прозрачности и blending эффектов

### Буферы и ресурсы

#### Particle Buffer
- Хранит массив структур Particle
- Выровнен для доступа GPU
- Размер частицы определяется layout’ом `Particle` (в текущем коде это 96 байт)

#### Simulation Parameters Buffer
- Содержит глобальные параметры симуляции
- Передается в compute шейдеры
- В текущем layout размер буфера составляет 272 байта

#### Uniform Buffers
- Матрицы трансформации
- Параметры камеры
- Настройки эффектов

## Ключевые возможности Metal

### 1. Compute Shaders
- Параллельная обработка частиц
- Физическая симуляция на GPU
- Оптимизированные алгоритмы

### 2. Render Pipelines
- Эффективная визуализация
- Поддержка различных эффектов
- Высокая производительность

### 3. Buffer Management
- Эффективное управление памятью
- Минимизация копий данных
- Потокобезопасный доступ

### 4. Synchronization
- Правильная синхронизация CPU/GPU
- Fence и event системы
- Оптимизация конвейера команд

## Расширяемые шейдерные блоки

Внутри `Core/Utils.h` и `Effects/Lighting.h` есть helper-функции, которые пока не используются в основном pipeline, но специально сохранены как точки расширения:

- `randomChaoticMotion()` и `fractalChaos()` - альтернативные профили движения
- `applyGlobalLight()`, `calculateAmbientOcclusion2D()`, `applyLightScattering()` - state-based lighting helpers

Эти функции позволяют добавлять новые режимы без переписывания базового render path.

## Когда что использовать

### `IDLE`
- Используй для спокойного состояния без сильной визуальной нагрузки.
- Подходит для минимального свечения и мягкой анимации.
- Основной путь: `fragmentParticle()` + `applyStateLighting()`.

### `CHAOTIC`
- Используй для активного, живого движения частиц.
- Основной motion-путь сейчас идет через `turbulentMotion()`.
- Подходит для динамичных сцен, где частицы должны "дышать" и смещаться с характером.

### `COLLECTING`
- Используй, когда частицы должны собираться в цель.
- Основной акцент идет на физику сбора и аккуратное освещение.
- Для этого режима подходит мягкий glow без агрессивных эффектов.

### `COLLECTED`
- Используй для стабильного финального состояния после сбора.
- Частицы должны выглядеть собранными и завершенными, без лишней динамики.
- Хорошо подходит для статичного, читаемого результата.

### `LIGHTNING_STORM`
- Используй для самого выразительного и энергичного режима.
- Здесь включаются электрические цвета, вспышки, zigzag-молнии и усиление яркости.
- Основной путь рендера остается `fragmentParticle()`, а state-based расширения лежат в lighting helpers.

## Feature Map

| State | Motion | Lighting | Alpha | Intended feel |
| --- | --- | --- | --- | --- |
| `IDLE` | Минимальный, мягкий | Слабый ambient glow | Стандартная | Спокойное ожидание |
| `CHAOTIC` | `turbulentMotion()` | Soft glow, state-based accents | Усиленная для читаемости | Живой, динамичный хаос |
| `COLLECTING` | Движение к цели | Мягкий glow + rim акценты | Полная видимость | Контролируемый сбор |
| `COLLECTED` | Фиксация на цели | Стабильное, теплое свечение | Полная видимость | Завершенное состояние |
| `LIGHTNING_STORM` | Дерганая турбулентность + импульсы | Электрические цвета, вспышки, молнии | Полная непрозрачность | Максимально энергичный режим |

## Activation Rules

### `updateParticles()`
1. Сначала выбирается активный режим симуляции.
2. Для `COLLECTING` применяется движение к цели и фиксация у цели.
3. Для `COLLECTED` частицы фиксируются на target position без дальнейшей интеграции.
4. Для `LIGHTNING_STORM` применяется электрическая force-модель и color modulation.
5. Для `IDLE` и `CHAOTIC` используется `turbulentMotion()` как основной motion path.
6. После motion применяется boundary handling и расчет размера частицы.

### `fragmentParticle()`
1. Сначала вычисляется форма частицы через `pointCoord` и `dist`.
2. Затем выбирается базовый цвет и режим рендеринга.
3. Для `LIGHTNING_STORM` включаются электрические цвета, вспышки и zigzag молнии.
4. Для `CHAOTIC` используется layered turbulence + bloom, а `COLLECTED` получает мягкий glow и rim accent.
5. Для `IDLE`, `COLLECTING` и `LIGHTNING_STORM` применяется `calculateParticle2DLighting()` с state-based lighting helpers.
6. В конце рассчитывается alpha в зависимости от состояния и визуального режима.

## Оптимизации производительности

### SIMD Operations
- Векторизованные вычисления
- Accelerate фреймворк интеграция
- Оптимизированные математические операции

### Memory Layout
- Выравнивание структур данных
- Минимизация паддинга
- Эффективный доступ к памяти

### Pipeline State Caching
- Предварительная компиляция шейдеров
- Кэширование pipeline states
- Быстрое переключение конфигураций

## Структура шейдеров

```
Shaders/
├── Common.h          # Общие структуры и константы
├── Core/
│   ├── Common.h      # Общие определения
│   └── Utils.h       # Вспомогательные функции
├── Compute/
│   ├── Physics.h     # Физика частиц
│   └── Simulation.h  # Логика симуляции
├── Effects/
│   └── Lighting.h    # Освещение и эффекты
└── Rendering/
    └── Basic.h       # Базовый рендеринг
```

## Использование в коде

### Инициализация Metal

```swift
let device = MTLCreateSystemDefaultDevice()
let renderer = MetalRenderer(device: device, logger: logger)
try renderer.setupPipelines()
```

### Настройка буферов

```swift
try renderer.setupBuffers(particleCount: 10000)
```

### Рендеринг кадра

```swift
func draw(in view: MTKView) {
   // Получить command buffer
   guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

   // Обновить симуляцию
   updateSimulation(commandBuffer)

   // Рендерить частицы
   renderParticles(commandBuffer, view)

   // Представить кадр
   commandBuffer.present(view.currentDrawable!)
   commandBuffer.commit()
}
```

## Совместимость

- **iOS target** - текущий целевой платформенный таргет проекта
- Другие Apple-платформы не входят в текущую сборку

## Производительность

### Метрики
- **ФПС**: 60+ кадров в секунду для 10k частиц
- **Задержка**: <16мс на кадр
- **Память**: Оптимизированное использование GPU памяти

### Оптимизации
- **Instancing**: Эффективное рендеринг множественных объектов
- **LOD**: Уровни детализации для дальних частиц
- **Culling**: Отсечение невидимых частиц

## Отладка и профилирование

### Metal Debugger
- Встроенные инструменты Xcode
- GPU Frame Capture
- Анализ производительности

### Performance Counters
- Измерение GPU utilization
- Мониторинг памяти
- Анализ bottleneck'ов
