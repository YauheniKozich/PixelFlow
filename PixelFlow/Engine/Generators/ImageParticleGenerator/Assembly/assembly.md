# Assembly - Сборка частиц

Преобразование сэмплов пикселей в готовые структуры Particle.

## Файлы

### ParticleAssembler.swift
**Сборщик частиц из сэмплов**

**Основная функция:**
Преобразует массив `Sample` (координаты и цвета пикселей) в массив `Particle` (структуры для Metal рендеринга).

**Процесс сборки:**

1. **Масштабирование координат**
   ```
   imageX (0...imageWidth) → screenX (0...screenWidth)
   imageY (0...imageHeight) → screenY (0...screenHeight)
   ```

2. **Назначение цветов**
   - Копирование цвета из сэмпла
   - Установка оригинального цвета для анимаций

3. **Настройка размеров**
   - Выбор размера в зависимости от качества
   - Добавление случайности для естественности

4. **Инициализация свойств**
   - Позиция, скорость, целевая позиция
   - Размеры (текущий и базовый)
   - Время жизни и другие параметры

**Конфигурация размеров:**
```swift
let sizeRange: ClosedRange<Float> = config.qualityPreset == .ultra ? 1.0...12.0 :
                                   config.qualityPreset == .high ? 2.0...10.0 :
                                   config.qualityPreset == .standard ? 3.0...8.0 : 4.0...6.0
```

## Входные данные

**Sample array** - результаты сэмплинга:
```swift
struct Sample {
   let x: Int          // координата X в изображении
   let y: Int          // координата Y в изображении
   let color: SIMD4<Float> // RGBA цвет пикселя
}
```

## Выходные данные

**Particle array** - готовые частицы для Metal:
```swift
struct Particle {
   var position: SIMD3<Float>        // текущая позиция
   var velocity: SIMD3<Float>        // скорость
   var targetPosition: SIMD3<Float>  // целевая позиция
   var color: SIMD4<Float>           // текущий цвет
   var originalColor: SIMD4<Float>   // оригинальный цвет
   var size: Float                   // текущий размер
   var baseSize: Float               // базовый размер
   var life: Float                   // время жизни
   var idleChaoticMotion: UInt32     // флаги поведения
}
```

## Оптимизации

- **Предварительное выделение памяти** для массива частиц
- **Пакетная обработка** сэмплов
- **Минимизация аллокаций** в циклах
- **SIMD-friendly структуры** для Metal