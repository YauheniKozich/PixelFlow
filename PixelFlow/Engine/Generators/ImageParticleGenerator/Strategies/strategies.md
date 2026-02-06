# Generation Strategies - Стратегии генерации частиц

Стратегии управления процессом генерации частиц из изображений.

## Обзор

Стратегии генерации определяют порядок и способ выполнения стадий генерации: анализ изображения, сэмплинг пикселей, сборка частиц и кэширование результатов. Фактический план учитывает зависимости, приоритеты и допустимый параллелизм, а стадия кэширования пропускается при `enableCaching = false`.

## Доступные стратегии

### SequentialStrategy (Последовательная)
**По умолчанию, последовательное выполнение стадий**

- **Порядок:** Анализ → Сэмплинг → Сборка → Кэширование
- **Параллелизм:** Нет
- **Преимущества:** Простота, предсказуемость
- **Использование:** Для большинства случаев, тестирование

### ParallelStrategy (Параллельная)
**Параллельное выполнение независимых стадий**

- **Порядок:** Анализ → Сэмплинг → Сборка → Кэширование
- **Параллелизм:** Разрешает параллелить независимые стадии (фактический параллелизм ограничен зависимостями и `maxConcurrentOperations`)
- **Преимущества:** Лучшая производительность на многоядерных системах
- **Использование:** Для больших изображений, высокая производительность

### AdaptiveStrategy (Адаптивная)
**Умное планирование на основе конфигурации**

- **Порядок:** Динамический, зависит от параметров
- **Параллелизм:** Адаптивный, в зависимости от сложности
- **Преимущества:** Оптимизация под конкретные условия
- **Использование:** Для сложных сценариев, автоматическая оптимизация

## Архитектура

Все стратегии реализуют протокол `GenerationStrategyProtocol`:

```swift
protocol GenerationStrategyProtocol {
   var executionOrder: [GenerationStage] { get }
   func canParallelize(_ stage: GenerationStage) -> Bool
   func dependencies(for stage: GenerationStage) -> [GenerationStage]
   func priority(for stage: GenerationStage) -> Operation.QueuePriority
   func validate(config: ParticleGenerationConfig) throws
   func estimateExecutionTime(for config: ParticleGenerationConfig) -> TimeInterval
   func isOptimal(for config: ParticleGenerationConfig) -> Bool
}
```

## Стадии генерации

- **Analysis:** Анализ изображения, расчет метрик
- **Sampling:** Выбор важных пикселей по стратегии сэмплинга
- **Assembly:** Создание частиц из сэмплов
- **Caching:** Сохранение результатов для повторного использования

## Выбор стратегии

| Стратегия | Производительность | Сложность | Рекомендации |
|-----------|-------------------|-----------|--------------|
| Sequential | Средняя | Низкая | По умолчанию, простые случаи |
| Parallel | Высокая | Средняя | Большие изображения |
| Adaptive | Адаптивная | Высокая | Специфические требования |

## Использование

```swift
let pipeline = GenerationPipeline(
    analyzer: analyzer,
    sampler: sampler,
    assembler: assembler,
    strategy: ParallelStrategy(logger: logger),
    context: context,
    logger: logger
)
let coordinator = GenerationCoordinator(pipeline: pipeline, ...)
