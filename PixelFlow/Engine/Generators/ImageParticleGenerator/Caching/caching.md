# Caching - Кэширование результатов

Умное кэширование для ускорения повторных генераций частиц.

## Файлы

### CacheManager.swift
**Менеджер кэширования с LRU стратегией**

## Основные компоненты

### DefaultCacheManager
**Основная реализация кэширования**

**Особенности:**
- Потокобезопасность с `DispatchQueue`
- Автоматическая очистка по LRU (Least Recently Used)
- Хэширование ключей для эффективности
- Управление размером кэша

### CacheEntry
**Структура записи кэша**

```swift
struct CacheEntry: Codable {
   let key: String        // хэшированный ключ
   let fileName: String   // имя файла на диске
   let size: Int          // размер в байтах
   let createdAt: Date    // время создания
   var lastAccessed: Date // время последнего доступа
}
```

### MemoryCache
**Дополнительный in-memory кэш**

Для часто используемых данных в памяти (опционально).

## Как работает кэширование

### 1. Генерация ключа
```swift
private func cacheKey() -> String {
   let components = [
       "\(image.width)x\(image.height)",  // размеры изображения
       "\(targetParticleCount)",          // количество частиц
       "\(config.qualityPreset)",         // пресет качества
       "\(config.samplingStrategy)"       // стратегия сэмплинга
   ]
   return "particles_" + components.joined(separator: "_")
}
```

### 2. Проверка кэша
```swift
if config.enableCaching,
  let cached = try cacheManager.retrieve([Particle].self, for: cacheKey()) {
   return cached // Возврат из кэша
}
```

### 3. Сохранение результата
```swift
if config.enableCaching {
   try cacheManager.cache(generatedParticles, for: cacheKey())
}
```

## Стратегия LRU

### Принцип работы
- **LRU (Least Recently Used)**: удаляются наименее недавно использованные записи
- **Управление размером**: автоматическая очистка при превышении лимита
- **Время доступа**: обновляется при каждом чтении

### Очистка кэша
```swift
private func cleanupIfNeeded(additionalSize: Int) throws {
   guard currentCacheSize + additionalSize > maxCacheSize else { return }

   // Сортировка по времени последнего доступа (старые сначала)
   let sortedEntries = cacheIndex.values.sorted { $0.lastAccessed < $1.lastAccessed }

   // Удаление старых записей
   var sizeToFree = currentCacheSize + additionalSize - maxCacheSize
   for entry in sortedEntries {
       // ... удаление файлов и обновление индекса
   }
}
```

## Хранение данных

### Формат файлов
- **JSON сериализация** для массивов Particle
- **SHA256 хэширование** ключей для уникальности имен файлов
- **Атомарная запись** для предотвращения повреждения данных

### Структура директорий
```
~/Library/Caches/ParticleGenerator/
├── cache_index.json          # Индекс кэша
├── a1b2c3d4e5f6.json         # Сериализованные частицы
├── f7g8h9i0j1k2.json         # Другие записи
└── ...
```

## Производительность

### Ускорение
- **Повторные вызовы**: ускорение в 10-100 раз
- **Большие изображения**: особенно эффективно для сложных изображений
- **Частые конфигурации**: кэшируются часто используемые настройки

### Ограничения размера
- **По умолчанию**: 100 МБ
- **Автоматическая очистка**: при превышении лимита
- **Настраиваемый лимит**: через `cacheSizeLimit`

## Управление кэшем

### Очистка
```swift
generator.clearCache() // Очистка кэша генератора
```

### Отключение
```swift
var config = ParticleGenerationConfig.default
config.enableCaching = false // Полностью отключить кэширование
```

### Мониторинг
- **Размер кэша**: отслеживается автоматически
- **Количество записей**: доступно через cacheIndex
- **Статистика доступа**: время создания и последнего использования

## Безопасность

### Потокобезопасность
- Все операции через `DispatchQueue` с барьерами
- Безопасный доступ из нескольких потоков
- Атомарные операции чтения/записи

### Обработка ошибок
- Graceful degradation при ошибках кэширования
- Продолжение работы без кэша при проблемах
- Валидация данных при десериализации