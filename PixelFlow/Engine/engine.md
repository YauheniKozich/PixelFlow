# Engine - Ядро симуляции частиц

Папка `Engine` содержит все компоненты ядра приложения PixelFlow, отвечающие за симуляцию и рендеринг частиц.

## Архитектура

```
Engine/
├── Generators/         # Генерация частиц из изображений
├── ParticleSystem/     # Основная логика симуляции
└── Shaders/            # GPU шейдеры для Metal
```

## Компоненты

### Generators (`ImageParticleGenerator`)
Модульная система генерации частиц из изображений с высокой производительностью.

**Основные возможности:**
- Анализ изображений (яркость, контраст, цвета)
- Умный сэмплинг пикселей по важности
- Адаптивная плотность частиц
- Кэширование результатов

### ParticleSystem
Основная бизнес-логика симуляции частиц.

**Компоненты:**
- `Core/` - основной класс ParticleSystem
- `Simulation/` - логика состояний и физики
- `Rendering/` - Metal рендеринг
- `Particles/` - структуры данных частиц
- `Models/` - модели данных
- `Utils/` - вспомогательные функции

### Shaders
Metal шейдеры для GPU-вычислений и рендеринга.

**Структура:**
- `Core/` - общие структуры и утилиты
- `Compute/` - вычислительные шейдеры (физика)
- `Rendering/` - рендеринг (vertex/fragment)
- `Effects/` - визуальные эффекты (освещение)

## Взаимодействие компонентов

```
Пользователь → Assembly (MVVM) → Engine
                              ↓
                    ParticleSystem ← Generators
                              ↓
                          Shaders (GPU)
```

1. **Generators** создают частицы из изображений
2. **ParticleSystem** управляет симуляцией и использует Generators
3. **Shaders** выполняют GPU-вычисления для рендеринга
4. **Assembly** (MVVM слой) связывает Engine с UI

## Производительность

- **SIMD оптимизации** в Generators
- **Metal GPU acceleration** для рендеринга
- **Многопоточная обработка** анализа изображений
- **Эффективное кэширование** результатов

## Документация

- [ImageParticleGenerator](Generators/ImageParticleGenerator/image-particle-generator.md)
- [Shaders](Shaders/shaders.md)
- [ParticleSystem](ParticleSystem/particlesystem.md) - основная система симуляции частиц

## Использование

Engine используется через слой Assembly:

```swift
// Создание компонентов через Assembly
let viewController = ParticleAssembly.assemble()
```

Все публичные API доступны через протоколы и основные классы в соответствующих модулях.
