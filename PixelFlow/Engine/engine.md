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
Генерация частиц из изображений.

### ParticleSystem
Симуляция, состояние и рендеринг частиц.

### Shaders
Metal-шейдеры для вычислений и рендеринга.

## Взаимодействие компонентов

```
Пользователь → Assembly (MVVM) → Engine
                              ↓
                    ParticleSystem ← Generators
                              ↓
                          Shaders (GPU)
```

1. **Generators** создают частицы из изображений
2. **ParticleSystem** управляет симуляцией и рендерингом
3. **Shaders** выполняют GPU-вычисления
4. **Assembly** (MVVM слой) связывает Engine с UI

## Производительность

- **SIMD** в Generators
- **Metal GPU** для рендеринга
- **Многопоточная обработка** анализа изображений
- **Кэширование** результатов

## Документация

- [ImageParticleGenerator](Generators/ImageParticleGenerator/image-particle-generator.md)
- [Shaders](Shaders/shaders.md)
- [ParticleSystem](ParticleSystem/particlesystem.md) - основная система симуляции частиц

## Использование

Engine instances are created explicitly by `AppCompositionRoot` for each particle view. The presentation layer interacts with the resulting system through `ParticleSystemControlling`; image generation is connected through `ParticleGeneratorProtocol`.

Все публичные API доступны через протоколы и основные классы в соответствующих модулях.
