# Shaders Directory

## Архитектура шейдеров Metal для проекта PixelFlow

Папка `Engine/Shaders/` содержит модульную организацию Metal-шейдеров.

## Структура файлов

### 📁 Core/ - Ядро системы
#### Common.h
**Назначение**: Общие структуры данных
- `Particle` - структура частицы с позицией, скоростью, цветом и размерами
- `SimulationParams` - параметры симуляции для передачи в шейдеры

#### Utils.h
**Назначение**: Вспомогательные функции
- `hash(float n)` - функция хэширования для генерации случайных чисел
- `noise(float3 p)` - функция шума для создания хаотичных эффектов
- `turbulentMotion` теперь генерирует пространственно-коррелированное поле с учетом позиции частицы
- `randomChaoticMotion()` и `fractalChaos()` уже используются как дополнительные варианты движения в отдельных режимах

### 📁 Rendering/ - Рендеринг
#### Basic.h
**Назначение**: Базовые vertex и fragment шейдеры для рендеринга частиц
- Vertex трансформации (`vertexParticle()`) с учетом положения частиц в NDC [-1,1]
- Fragment шейдеры (`fragmentParticle()`) для освещения и цвета
- `fragmentParticlePerformance()` - fast-path, используемый для `QualityPreset.draft`
- Cinematic lighting: glow, bloom, state-based эффекты
- Lightning эффекты: электрические молнии с zigzag эффектом
- Альфа-блендинг: state-based прозрачность
- Примечание: все позиции частиц теперь в **NDC [-1,1]**, а `screenSize` используется для нормализации subpixel offsets и screen-space эффектов

### 📁 Compute/ - Вычислительные шейдеры
#### Physics.h
**Назначение**: Физические расчеты
- Динамика частиц (`updateParticles()`)
- Расчеты силовых полей
- Обнаружение столкновений

#### Simulation.h
**Назначение**: Логика симуляции
- Конечный автомат состояний (idle, chaotic, collecting, collected)
- Временная интеграция (Euler, Verlet методы)
- Граничные условия (отскок, тор, ограничение)
- Управление параметрами симуляции в реальном времени

### 📁 Effects/ - Визуальные эффекты
#### Lighting.h
**Назначение**: Система освещения и световые эффекты для частиц
- Glow эффекты: радиальное свечение от центра частиц
- Bloom: свечение ярких областей
- Rim lighting, Fresnel эффекты
- Ambient и directional lighting
- State-based эффекты: разные типы освещения для разных состояний симуляции
- `applyGlobalLight()`, `calculateAmbientOcclusion2D()` и `applyLightScattering()` - state-based lighting helper'ы, уже подключенные в отдельных режимах
- Текущий основной путь освещения проходит через `calculateParticle2DLighting()` и `applyStateLighting()`

## Основной файл шейдера

Основной файл `ParticleShader.metal` импортирует модульные компоненты:
1. `Engine/Shaders/Core/Common.h` - общие структуры данных
2. `Engine/Shaders/Core/Utils.h` - вспомогательные функции
3. `Engine/Shaders/Compute/Physics.h` - compute шейдер для физики частиц
4. `Engine/Shaders/Rendering/Basic.h` - базовые vertex/fragment шейдеры и рендеринг частиц с эффектами
5. `Engine/Shaders/Effects/Lighting.h` - система освещения (glow, bloom, rim, ambient, state-based эффекты)
6. `ParticleShader.metal` - главный Metal шейдер (компилирует все компоненты)

## Активные компоненты

- **Compute/Physics.h** - физика частиц (`updateParticles()`)
- **Compute/Simulation.h** - логика симуляции
- **Core/Common.h** - структуры данных (`Particle`, `SimulationParams`)
- **Core/Utils.h** - вспомогательные функции
- **ParticleShader.metal** - основной Metal-шейдер

### 🧩 Расширяемые точки
- **Core/Utils.h** - `randomChaoticMotion()` и `fractalChaos()` уже используются в отдельных режимах как дополнительные профили движения
- **Effects/Lighting.h** - `applyGlobalLight()`, `calculateAmbientOcclusion2D()` и `applyLightScattering()` уже участвуют в state-based lighting для отдельных режимов
- **Rendering/Basic.h** - `fragmentParticlePerformance()` оставлен как упрощенный fragment path для режима производительности

## Матрица назначения helper'ов

| Файл | Функция | Статус | Назначение |
| --- | --- | --- | --- |
| `Core/Utils.h` | `turbulentMotion()` | Активно используется | Основной хаотичный motion для текущих режимов |
| `Core/Utils.h` | `randomChaoticMotion()` | Активно используется в selected states | Дополнительный chaotic profile для storm branch |
| `Core/Utils.h` | `fractalChaos()` | Активно используется в selected states | Многослойный motion-эффект для chaotic state |
| `Effects/Lighting.h` | `calculateParticle2DLighting()` | Активно используется | Основной lighting path для рендеринга частиц |
| `Effects/Lighting.h` | `applyStateLighting()` | Активно используется | State-based модификация освещения |
| `Effects/Lighting.h` | `applyGlobalLight()` | Активно используется в selected states | Глобальный направленный свет для state-based lighting |
| `Effects/Lighting.h` | `calculateAmbientOcclusion2D()` | Активно используется в selected states | Плотностное затемнение для collecting / idle lighting |
| `Effects/Lighting.h` | `applyLightScattering()` | Активно используется в selected states | Рассеяние света и мягкие ореолы для storm lighting |
| `Rendering/Basic.h` | `fragmentParticle()` | Активно используется | Основной fragment path в текущем pipeline |
| `Rendering/Basic.h` | `fragmentParticlePerformance()` | Активно используется для `QualityPreset.draft` | Упрощенный fragment path для режима производительности |

## Преимущества модульной архитектуры

1. **Логическая организация** - каждый компонент в своей папке
2. **Переиспользование** - компоненты можно использовать в разных проектах
3. **Читаемость** - четкая структура с документацией
4. **Один файл компиляции** - Metal собирает шейдеры вместе

## Компиляция

Все файлы компилируются вместе через основной файл `ParticleShader.metal`. Metal компилятор автоматически разрешает зависимости между файлами.
