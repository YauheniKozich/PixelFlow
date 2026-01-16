# Core - Ядро системы

Главная папка с основными компонентами ImageParticleGenerator.

## Файлы

### GenerationCoordinator.swift
**Главный координатор системы**

- Управляет всем процессом генерации частиц
- Координирует работу конвейера и компонентов
- Предоставляет публичный API для пользователей
- Обрабатывает асинхронные операции, кэширование и отмену
- Отслеживает прогресс и ошибки

**Ключевые методы:**
- `generateParticles()` - основная асинхронная генерация
- `cancelGeneration()` - отмена процесса
- `clearCache()` - очистка кэша

**Фабрика:** `GenerationCoordinatorFactory.makeCoordinator()`

### GenerationPipeline.swift
**Конвейер выполнения этапов генерации**

- Реализует последовательность стадий: анализ, сэмплинг, сборка, кэширование
- Поддерживает различные стратегии генерации
- Обеспечивает изоляцию и тестируемость компонентов

**Ключевые методы:**
- `execute()` - выполнение конвейера с прогрессом

### GenerationContext.swift
**Контекст выполнения генерации**

- Хранит промежуточные данные между стадиями
- Управляет состоянием генерации
- Обеспечивает потокобезопасность

### ImageParticleGeneratorToParticleSystemAdapter.swift
**Адаптер для интеграции с ParticleSystem**

- Преобразует результаты генерации для системы частиц
- Обеспечивает совместимость интерфейсов

## Протоколы системы

Основные протоколы определены в [`PixelFlow/Infrastructure/Protocols/GeneratorProtocols.swift`](PixelFlow/Infrastructure/Protocols/GeneratorProtocols.swift):

- `GenerationCoordinatorProtocol` - интерфейс координатора генерации
- `GenerationPipelineProtocol` - интерфейс конвейера выполнения
- `ImageAnalyzerProtocol` - анализ изображений
- `PixelSamplerProtocol` - сэмплинг пикселей
- `ParticleAssemblerProtocol` - сборка частиц
- `CacheManagerProtocol` - управление кэшем
- `GenerationStrategyProtocol` - стратегии выполнения

## Взаимодействие

```
Пользователь
   ↓
GenerationCoordinator (координатор)
   ↓
GenerationPipeline (конвейер)
   ↓
├── analysis.md (анализ)
├── sampling.md (сэмплинг)
├── assembly.md (сборка)
└── caching.md (кэширование)
```

**Архитектура:**
- **Coordinator**: Управление жизненным циклом, API
- **Pipeline**: Логика последовательности стадий
- **Context**: Обмен данными между стадиями
- **Adapter**: Интеграция с внешними системами