# PixelFlow

PixelFlow превращает исходные изображения в анимированные системы частиц с помощью обработки на CPU и вычислений и рендеринга на Metal. Каждое представление частиц владеет собственной симуляцией и GPU-ресурсами; общие сервисы приложения создаются явным корнем композиции.

## Сборка приложения

```text
AppDelegate
    ↓
AppCompositionRoot
    ↓
ParticleViewModel / ParticleViewController
    ↓
ParticleSystem для отдельного представления
```

`AppCompositionRoot` владеет сервисами уровня приложения и создаёт отдельный граф зависимостей для каждого `MTKView`. Система частиц владеет собственным хранилищем частиц, симуляцией, рендерером и координатором генерации. Рендерер назначается делегатом `MTKView`; рендерер и контроллер хранят слабые ссылки на представление. Общие сервисы не удерживают системы частиц или представления.

## Путь от изображения до кадра

```text
Изображение
  ↓
Анализ
  ↓
Сэмплирование
  ↓
Сборка частиц
  ↓
Хранилище частиц
  ↓
Симуляция
  ↓
Вычисления Metal
  ↓
Рендеринг Metal
```

Анализ изображения, сэмплирование пикселей и сборка частиц подготавливают исходные данные частиц. `ParticleStorage` владеет GPU-буфером частиц для конкретного представления. `SimulationEngine` обновляет состояние симуляции и время, вычисления Metal — позиции частиц, а рендеринг Metal отображает каждый кадр. Перед изменением общих буферов рендерер синхронизирует обновления на CPU с кадрами, обработка которых на GPU ещё не завершена.

## Структура проекта

```text
PixelFlow/
├── App/
│   ├── AppDelegate.swift
│   ├── SceneDelegate.swift
│   └── Composition/AppCompositionRoot.swift
├── Presentation/Particle/
│   ├── ParticleViewController.swift
│   ├── ParticleViewModel.swift
│   ├── RenderView.swift
│   └── RenderView+MetalKit.swift
├── Engine/
│   ├── Generators/ImageParticleGenerator/
│   ├── ParticleSystem/
│   ├── Shaders/
│   └── GraphicsUtils.swift
├── Infrastructure/
│   ├── Protocols/
│   └── Services/
├── Errors/
└── Resources/
```

## Возможности

- Генерация частиц на основе изображений с пресетами качества Draft, Standard, High и Ultra.
- Симуляция и рендеринг на GPU с помощью вычислительных и графических конвейеров Metal.
- Отдельный жизненный цикл системы частиц для каждого представления при общих сервисах приложения для изображений, журналирования, обработки ошибок и управления памятью.
- Синхронизация CPU и GPU: перед изменением общих буферов учитывается обработка уже отправленных кадров.

## Документация

- [Генератор частиц из изображения](PixelFlow/Engine/Generators/ImageParticleGenerator/image-particle-generator.md)
- [Обзор Engine](PixelFlow/Engine/engine.md)
- [Система частиц](PixelFlow/Engine/ParticleSystem/particlesystem.md)
- [Руководство по шейдерам](PixelFlow/Engine/Shaders/shaders.md)
- [Обработка ошибок](PixelFlow/Errors/errors.md)
- [Ресурсы](PixelFlow/Resources/resources.md)

## Требования

- Целевая платформа iOS задаётся в проекте Xcode.
- Версия Xcode должна поддерживать используемую проектом цепочку инструментов Metal.
- Версия Swift задаётся в настройках проекта Xcode.

## Лицензия

MIT License. См. файл [LICENSE](LICENSE).
