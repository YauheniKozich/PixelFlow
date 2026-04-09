# Руководство по использованию шейдеров PixelFlow

## Быстрый старт

Шейдеры проекта содержат базовые и state-based эффекты освещения для частиц.

---

## ДОСТУПНЫЕ ЭФФЕКТЫ ОСВЕЩЕНИЯ

### 1. Простое освещение частиц
```metal
// Используйте calculateParticle2DLighting из Lighting.h
// Позиция частицы должна быть в пикселях, screenSize нужен для нормализации
float3 litColor = calculateParticle2DLighting(
    baseColor,           // базовый цвет частицы
    screenPos,           // позиция в пикселях
    screenSize,          // размер экрана для NDC-конверсии
    dist,                // расстояние от центра частицы (0-1)
    time,                // время для анимации
    state,               // состояние симуляции
    brightnessBoost      // усиление яркости
);
```

### 2. Glow эффект
```metal
// Радиальное свечение от центра частицы с использованием констант GLOW_FALLOFF_POWER и GLOW_BASE_INTENSITY
float glow = calculateGlow(dist, GLOW_FALLOFF_POWER, GLOW_BASE_INTENSITY);
float3 glowingColor = baseColor + float3(glow);
```

### 3. State-based освещение
```metal
// Разные эффекты для разных состояний симуляции
// Позиция частицы должна быть в пикселях, screenSize нужен для нормализации
float3 color = applyStateLighting(
    baseColor, position, screenSize, dist, time, state
);
// Автоматически выбирает: idle, chaotic, collecting, collected, storm
```

---

## РАСШИРЯЕМЫЕ HELPER'Ы

Некоторые функции уже подключены в отдельных режимах, а часть все еще остается как готовая точка расширения для новых сценариев.

### Движение
```metal
// Альтернативные варианты хаотичного движения
float2 chaoticA = randomChaoticMotion(position, time, particleId);
float2 chaoticB = fractalChaos(position, time, particleId);
```

### Освещение
```metal
// Дополнительные lighting helpers для state-based режимов
float3 globalLight = applyGlobalLight(color, ndcPosition, lightColor, intensity);
float ao = calculateAmbientOcclusion2D(position, particleDensity);
float3 scattered = applyLightScattering(color, position, lightSource, intensity);
```

### Производительность
```metal
// Упрощенный fragment path для переключения качества через draft preset
float4 fastColor = fragmentParticlePerformance(...);
```

При `QualityPreset.draft` renderer автоматически выбирает performance path.

---

## КРАТКАЯ КАРТА ФУНКЦИЙ

- `turbulentMotion()` - основной chaotic motion в текущем pipeline
- `randomChaoticMotion()` - дополнительный chaotic motion для storm-ветки
- `fractalChaos()` - более сложный motion с несколькими октавами для chaotic state
- `calculateParticle2DLighting()` - основной путь освещения
- `applyStateLighting()` - state-based модификация освещения
- `applyGlobalLight()` - state-based helper для общего света
- `calculateAmbientOcclusion2D()` - state-based helper для ambient occlusion
- `applyLightScattering()` - state-based helper для рассеяния света
- `fragmentParticle()` - основной fragment path
- `fragmentParticlePerformance()` - fast-path для производительности

---

## ДОСТУПНЫЕ ФОРМЫ ЧАСТИЦ

В PixelFlow частицы рендерятся как точки с программным освещением. Формы определяются через фрагментный шейдер:

```metal
// Стандартная круглая форма
float2 uv = pointCoord * 2.0 - 1.0;  // -1 to 1
float dist = length(uv);             // 0 to 1.414
float alpha = 1.0 - smoothstep(0.9, 1.0, dist); // мягкие края

return float4(color, alpha);
```

### Доступные формы через освещение:
- **Круглая**: стандартная форма с плавными краями
- **Звездная**: через state-based эффекты (chaotic mode)
- **Искровая**: через электрические эффекты (lightning storm)
- **Светящаяся**: через glow и bloom эффекты

---

## СПЕЦИАЛЬНЫЕ РЕЖИМЫ

### State-based эффекты (автоматические)
```metal
// В Basic.h автоматически применяется в зависимости от состояния:

// IDLE: минимальное ambient освещение
// CHAOTIC: динамическое освещение с pulsing и turbulentMotion — пространственно-коррелированное поле, учитывающее позицию
// COLLECTING: soft glow + rim highlight
// COLLECTED: intense energy effect
// LIGHTNING_STORM: электрические эффекты + молнии
```

### Lightning эффекты
```metal
// В режиме LIGHTNING_STORM:
// - Электрические цвета с турбулентностью
// - Zigzag молнии каждые 4 секунды
// - Spark эффекты
// - Energy waves
```

---

## ДОСТУПНЫЕ ВОЗМОЖНОСТИ

### Основные структуры данных
```metal
// Particle (определено в Common.h)
struct Particle {
    float3 position, velocity, targetPosition;
    float4 color, originalColor;
    float size, baseSize, life;
    uint idleChaoticMotion;
};

// SimulationParams (определено в Common.h)
struct SimulationParams {
    uint state, pixelSizeMode, colorsLocked;
    float deltaTime, collectionSpeed, brightnessBoost;
    float2 screenSize;
    float minParticleSize, maxParticleSize, time;
    uint particleCount, idleChaoticMotion;
};
```

### Основные функции освещения (Lighting.h)
```metal
// Простое глобальное освещение для state-based режимов
float3 applyGlobalLight(float3 color, float2 position,
                       float3 lightColor, float intensity);

// Радиальный glow
float calculateGlow(float dist, float power, float intensity);

// Полное освещение частиц
float3 calculateParticle2DLighting(float3 color, float2 position,
                                  float2 screenSize, float dist, float time, int state, float brightnessBoost);

// State-based эффекты
float3 applyStateLighting(float3 color, float2 position,
                         float2 screenSize, float dist, float time, int state);
```

### Константы состояний (Simulation.h)
```metal
#define SIMULATION_STATE_IDLE 0
#define SIMULATION_STATE_CHAOTIC 1
#define SIMULATION_STATE_COLLECTING 2
#define SIMULATION_STATE_COLLECTED 3
#define SIMULATION_STATE_LIGHTNING_STORM 4
```

---

## ЧТО НЕ РЕАЛИЗОВАНО (пока)

- PBR материалы и освещение
- HDR рендеринг и tone mapping
- SSAO, depth of field, motion blur
- Color grading, vignette, film grain
- Комплексные сцены с множеством эффектов
- Интерактивные эффекты (мышь, touch)

---
 **Начните здесь**: Изучите `Basic.h` и `Lighting.h` для понимания доступных функций освещения!
