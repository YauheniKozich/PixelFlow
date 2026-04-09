//
//  Basic.h - РЕНДЕРИНГ ЧАСТИЦ: Кисть художника на GPU
//  ====================================================
//
//  ЭТОТ ФАЙЛ - ХОЛСТ И КРАСКИ!
//  Здесь частицы превращаются в пиксели на экране.
//
//  Vertex шейдер берет частицы из памяти и размещает их в пространстве.
//  Fragment шейдер рисует каждую частицу с освещением и эффектами.
//
//  Это финальный этап: от абстрактных чисел к красивой картинке!
//  Каждая частица здесь оживает цветом и светом.
//
//  Автор: Yauheni Kozich
//  Создан: 31.10.25
//  Обновлен: 2025-01-10 - Добавлены подробные русские комментарии
//
//  📝 ОПИСАНИЕ: Создано маленьким, но не глупым ИИ под чутким руководством человека
//  🤖 ИИ: Помогал с формулировками и структурой комментариев
//  👨‍💻 Человек: Определял технические детали и архитектурные решения
//

#ifndef Basic_h
#define Basic_h

#include <metal_stdlib>
#include "../Core/Utils.h"
#include "../Compute/Simulation.h"
#include "../Effects/Lighting.h"
using namespace metal;

// ============================================================================
// КОНСТАНТЫ РЕНДЕРИНГА - ПАРАМЕТРЫ "ХУДОЖЕСТВЕННОГО СТИЛЯ"
// ============================================================================

// ОСНОВНЫЕ ПАРАМЕТРЫ ПРОЗРАЧНОСТИ
#define PARTICLE_ALPHA_THRESHOLD 0.01   // Минимальная прозрачность для отрисовки
#define PARTICLE_EDGE_SOFTNESS 0.95     // Увеличиваем размытость краев для сглаживания

// КОНСТАНТЫ ЭЛЕКТРИЧЕСКОЙ БУРИ - спецэффекты молний
#define STORM_BRIGHTNESS_MULTIPLIER 4.5    // Усиление яркости в буре
#define STORM_SIZE_MULTIPLIER_MIN 0.55     // Минимальный размер в буре
#define STORM_SIZE_MULTIPLIER_MAX 0.9      // Максимальный размер в буре
#define STORM_MAX_BRIGHTNESS 3.0           // Ограничение яркости (защита от ослепления)
#define STORM_SPARK_THRESHOLD 0.995        // Порог для искр (редкие вспышки)
#define STORM_CORE_SOFTNESS 0.7            // Мягкость ядра частицы
#define STORM_GLOW_BOOST 0.28              // Дополнительный ореол для мелких частиц
#define STORM_WAVE_SPATIAL_FREQ 15.0       // Частота волн турбулентности
#define STORM_ELECTRIC_UV_SCALE 8.0        // Масштаб электрических текстур
#define STORM_TIME_SCALE_1 3.0             // Скорость анимации 1
#define STORM_TIME_SCALE_2 2.0             // Скорость анимации 2
#define STORM_HUE_SPEED_1 4.0              // Скорость изменения цвета 1
#define STORM_HUE_SPEED_2 6.0              // Скорость изменения цвета 2

// КОНСТАНТЫ МОЛНИЙ - zigzag эффекты
#define LIGHTNING_BOLT_PERIOD 4.0          // Период молний (секунды)
#define LIGHTNING_BOLT_DURATION 0.5        // Длительность молнии (секунды)
#define LIGHTNING_BOLT_WIDTH 0.02          // Толщина молнии (тонкая)
#define LIGHTNING_BOLT_BRIGHTNESS 5.0      // Яркость молнии (очень яркая)
#define LIGHTNING_ZIGZAG_FREQ 30.0         // Частота зигзагов
#define LIGHTNING_ZIGZAG_AMOUNT 0.02       // Амплитуда зигзагов

// СУБПИКСЕЛЬНЫЕ СМЕЩЕНИЯ - для плавности при низком разрешении
#define SUBPIXEL_OFFSET_SCALE 0.5          // Масштаб смещения
#define SUBPIXEL_OFFSET_CENTER 0.25        // Центр смещения
#define SUBPIXEL_HASH_SEED_1 7.3           // Сид для X координаты
#define SUBPIXEL_HASH_SEED_2 13.7          // Сид для Y координаты

// ЗАЩИТНЫЕ КОНСТАНТЫ
#define MIN_PARTICLE_SIZE 0.1              // Минимальный размер частицы

// РЕЖИМЫ КАЧЕСТВА ОСВЕЩЕНИЯ
#define LIGHTING_QUALITY_LOW 0             // Только простое свечение
#define LIGHTING_QUALITY_MEDIUM 1          // Свечение + эффекты состояний
#define LIGHTING_QUALITY_HIGH 2            // Полное освещение с блумом

// КООРДИНАТНАЯ СИСТЕМА
#define NDC_COORDINATE_SYSTEM 1            // Частицы используют NDC [-1, 1], а не экранные [0, 1]

// ============================================================================
// COLOR SPACE HELPERS
// ============================================================================
// Particle colors come from CGImage/PixelCache in sRGB space, while the MTKView
// renders into an sRGB framebuffer (bgra8Unorm_srgb). Convert to linear before
// applying lighting, so the GPU can do the correct sRGB encoding at output.
static inline float3 srgbToLinear(float3 c) {
    float3 low = c / 12.92;
    float3 high = pow((c + 0.055) / 1.055, float3(2.4));
    return select(low, high, c > 0.04045);
}

// ============================================================================
// VERTEX ШЕЙДЕР - РАЗМЕЩЕНИЕ ЧАСТИЦ В ПРОСТРАНСТВЕ
// ============================================================================

/*
    Vertex шейдер - это как "распределитель ролей" в театре.

    Он берет частицы из буфера GPU и размещает каждую на сцене.
    Определяет размер, позицию, цвет - все внешние атрибуты.

    Вход: сырые данные частицы
    Выход: готовая к рендерингу структура с позицией и свойствами
*/

struct VertexOut {
    float4 position [[position]];        // Позиция в clip space (обязательно!)
    float pointSize [[point_size]];      // Размер точки в пикселях
    float4 color;                        // Цвет частицы
    float brightnessBoost;               // Усиление яркости
    float collectionSpeed;               // Скорость сбора (для анимации)
    float2 screenPos;                    // Позиция на экране (для освещения)
};

/*
    ВЫЧИСЛЕНИЕ СУБПИКСЕЛЬНОГО СМЕЩЕНИЯ

    Для борьбы с "пиксельным" видом при низком разрешении.
    Добавляет случайное смещение к каждой частице.

    Это как добавление "случайности" к позициям,
    чтобы частицы не выглядели как на шахматной доске.
*/
static inline float2 getSubpixelOffset(uint vid, float2 screenSize, uint pixelSizeMode) {
    // Если включен пиксель-перфект режим - отключаем смещение
    if (pixelSizeMode != 0) {
        return float2(0.0, 0.0);
    }

    // Вычисляем случайное смещение для каждой частицы
    return float2(
        hash(float(vid) * SUBPIXEL_HASH_SEED_1) * SUBPIXEL_OFFSET_SCALE - SUBPIXEL_OFFSET_CENTER,
        hash(float(vid) * SUBPIXEL_HASH_SEED_2) * SUBPIXEL_OFFSET_SCALE - SUBPIXEL_OFFSET_CENTER
    ) / screenSize * 2.0;  // Нормализуем в clip space
}

/*
    ОСНОВНОЙ VERTEX ШЕЙДЕР

    Обрабатывает каждую частицу отдельно.
    Превращает мировые координаты в экранные.
*/
vertex VertexOut vertexParticle(
    device const Particle* particles [[buffer(0)]],    // Буфер частиц
    constant SimulationParams * params [[buffer(1)]],   // Параметры симуляции
    uint vid [[vertex_id]]                             // ID вершины (номер частицы)
) {
    // Читаем частицу из буфера
    Particle p = particles[vid];
   // float2 screenPos = p.position.xy;

    // ============================================================================
    // ИСПОЛЬЗОВАНИЕ КООРДИНАТ NDC
    // ============================================================================

    // Particle.position УЖЕ хранится в нормализованных координатах NDC [-1…1].
    // Это стандартное пространство Normalized Device Coordinates для Metal/GPU.
    float2 ndc = p.position.xy;
    if (params[0].pixelSizeMode == 2) {
        float2 safeScreen = max(params[0].screenSize, float2(1.0));
        float2 screenPos = (ndc * 0.5 + 0.5) * safeScreen;
        screenPos = floor(screenPos) + 0.5;
        ndc = (screenPos / safeScreen) * 2.0 - 1.0;
    }

    // ============================================================================
    // ПОДГОТОВКА ВЫХОДНОЙ СТРУКТУРЫ (КООРДИНАТЫ УЖЕ В CLIP SPACE)
    // ============================================================================

    VertexOut out;

    // Добавляем субпиксельное смещение для плавности в NDC space
    float2 subpixelOffset = getSubpixelOffset(vid, params[0].screenSize, params[0].pixelSizeMode);
    // ndc уже в clip space [-1, 1], просто добавляем смещение и выводим
    out.position = float4(ndc + subpixelOffset, 0.0, 1.0);

    // ============================================================================
    // РАСЧЕТ РАЗМЕРА ЧАСТИЦЫ
    // ============================================================================

    // Безопасные границы размера
    float safeMinSize = max(params[0].minParticleSize, MIN_PARTICLE_SIZE);
    float safeMaxSize = max(params[0].maxParticleSize, safeMinSize);

    // В режиме бури частицы становятся больше и заметнее
    if (params[0].state == SIMULATION_STATE_LIGHTNING_STORM) {
        safeMinSize *= STORM_SIZE_MULTIPLIER_MIN;
        safeMaxSize *= STORM_SIZE_MULTIPLIER_MAX;
    }

    // Размер частицы В ПИКСЕЛЯХ.
    // p.size трактуется как размер одного пикселя изображения после всех трансформаций.
    float pixelSize = max(p.size, safeMinSize);

    // В режиме бури частицы визуально увеличиваются
    if (params[0].state == SIMULATION_STATE_LIGHTNING_STORM) {
        pixelSize *= mix(STORM_SIZE_MULTIPLIER_MIN,
                         STORM_SIZE_MULTIPLIER_MAX,
                         hash(float(vid)));
    }

    // pointSize всегда в пикселях
    out.pointSize = clamp(pixelSize, safeMinSize, safeMaxSize);

    // ============================================================================
    // ПОДГОТОВКА ЦВЕТА И ПАРАМЕТРОВ
    // ============================================================================

    // Валидация цвета (защита от отрицательных/слишком ярких значений)
    out.color = float4(
        clamp(p.color.r, 0.0, 1.0),
        clamp(p.color.g, 0.0, 1.0),
        clamp(p.color.b, 0.0, 1.0),
        clamp(p.color.a, 0.0, 1.0)
    );

    // Передаем параметры для fragment шейдера
    out.brightnessBoost = params[0].brightnessBoost;
    out.collectionSpeed = params[0].collectionSpeed;
    // screenPos в пикселях нужен только для освещения
    // ВАЖНО: учитываем subpixelOffset, чтобы освещение совпадало с геометрией
    float2 finalNDC = ndc + subpixelOffset;
    out.screenPos = (finalNDC * 0.5 + 0.5) * params[0].screenSize;

    return out;
}

// ============================================================================
// FRAGMENT ШЕЙДЕР - РИСОВАНИЕ И ОСВЕЩЕНИЕ ЧАСТИЦ
// ============================================================================

/*
    Fragment шейдер - это как "маляр" в театре.

    Он рисует каждую частицу пиксель за пикселем.
    Добавляет свечение, цвета, эффекты - превращает точку в произведение искусства!

    Каждый пиксель частицы проходит через этот шейдер.
*/

/*
    ОСНОВНОЙ FRAGMENT ШЕЙДЕР

    Рисует частицу с полным набором эффектов освещения.
    Поддерживает разные режимы: буря, сбор, обычное состояние.
*/
fragment float4 fragmentParticle(
    VertexOut in [[stage_in]],                    // Данные от vertex шейдера
    float2 pointCoord [[point_coord]],            // Координаты внутри частицы (0-1)
    constant SimulationParams * params [[buffer(1)]] // Параметры симуляции
) {
    // ============================================================================
    // ПОДГОТОВКА КООРДИНАТ И ФОРМЫ ЧАСТИЦЫ
    // ============================================================================

    // Преобразование координат: (0,0) центр → (-1,-1) край
    float2 uv = pointCoord * 2.0 - 1.0;
    float dist = length(uv);  // Расстояние от центра

    float alpha = 1.0;
    if (params[0].pixelSizeMode == 0) {
        // Создаем круглую форму с мягкими краями
        alpha = 1.0 - smoothstep(1.0 - PARTICLE_EDGE_SOFTNESS, 1.0, dist);
    }

    // ============================================================================
    // ВЫБОР ЦВЕТА В ЗАВИСИМОСТИ ОТ СОСТОЯНИЯ
    // ============================================================================

    float3 col;  // Финальный цвет частицы
    float3 baseColor = srgbToLinear(in.color.rgb);

    // Pixel-perfect режим: без освещения и эффектов, только исходный цвет.
    // Это дает максимально точное соответствие исходному изображению.
    if (params[0].pixelSizeMode != 0 && params[0].state != SIMULATION_STATE_LIGHTNING_STORM) {
        return float4(baseColor, 1.0);
    }

    // СПЕЦИАЛЬНАЯ ОБРАБОТКА ЭЛЕКТРИЧЕСКОЙ БУРИ ⚡
    if (params[0].state == SIMULATION_STATE_LIGHTNING_STORM) {
        // ========================================================================
        // ЭЛЕКТРИЧЕСКАЯ БУРЯ - САМЫЙ ДРАМАТИЧНЫЙ РЕЖИМ
        // ========================================================================

        // Создаем "электрические" UV координаты с движением
        float2 electricUV = uv * STORM_ELECTRIC_UV_SCALE +
                           float2(params[0].time * STORM_TIME_SCALE_1,
                                 params[0].time * STORM_TIME_SCALE_2);

        // Генерируем сид для псевдо-случайности
        float electricSeed = dot(electricUV, float2(12.9898, 78.233));

        // ДИНАМИЧЕСКИЕ ЭЛЕКТРИЧЕСКИЕ ЦВЕТА - постоянно меняются
        float hue1 = hash(electricSeed) * TWO_PI + params[0].time * STORM_HUE_SPEED_1;
        float hue2 = hash(electricSeed + 100.0) * TWO_PI + params[0].time * STORM_HUE_SPEED_2;

        // Базовый цвет: электрический голубой/фиолетовый/бирюзовый
        col = float3(
            0.0 + 0.8 * abs(sin(hue1)),              // Красный канал
            0.2 + 0.6 * abs(sin(hue1 + 1.57)),       // Зеленый канал (сдвиг фазы)
            0.8 + 0.2 * abs(sin(hue2))               // Синий канал
        );

        // ДОБАВЛЯЕМ ТУРБУЛЕНТНОСТЬ - как плазма
        float turbulence = hash(electricSeed + params[0].time * 2.0) * 0.3;
        col += float3(0.1, 0.2, 0.4) * turbulence;

        // РЕДКИЕ ЯРКИЕ ИСКРЫ - впечатляющие вспышки
        float sparkSeed = dot(uv * 100.0, float2(1.0, 1.0)) + params[0].time * 10.0;
        if (hash(sparkSeed) > STORM_SPARK_THRESHOLD) {
            col = float3(3.0, 3.0, 3.0);  // Белые вспышки
        }

        // МЕЛКИЙ ЯДЕРНЫЙ ОРЕОЛ - делаем частицы визуально тоньше и "электричнее"
        float stormCore = pow(max(1.0 - dist, 0.0), 3.2);
        col += float3(0.25, 0.45, 0.75) * stormCore * STORM_GLOW_BOOST * STORM_CORE_SOFTNESS;

        // ЭНЕРГЕТИЧЕСКИЕ ВОЛНЫ - модуляция яркости
        float waveFreq = 8.0 + hash(electricSeed) * 4.0;
        float wave = sin(params[0].time * waveFreq + length(uv) * STORM_WAVE_SPATIAL_FREQ) * 0.4 + 0.6;
        col *= wave;

        // МАКСИМАЛЬНОЕ УСИЛЕНИЕ ЯРКОСТИ для видимости бури
        col *= STORM_BRIGHTNESS_MULTIPLIER;

        // ========================================================================
        // МОЛНИИ - ZIGZAG ЭФФЕКТЫ ⚡ (SCREEN SPACE, КОРРЕКТНО)
        // ========================================================================

        float boltTime = fmod(params[0].time * 0.3, LIGHTNING_BOLT_PERIOD);

        if (boltTime < LIGHTNING_BOLT_DURATION) {
            float boltProgress = boltTime / LIGHTNING_BOLT_DURATION;

            // screenPos в пикселях → нормализуем в NDC
            float2 pixelNDC = (in.screenPos / params[0].screenSize) * 2.0 - 1.0;

            // Глобальная молния в NDC
            float2 boltStart = float2(
                hash(floor(params[0].time) * 7.389) * 2.0 - 1.0,
                1.0
            );

            float2 boltEnd = float2(
                hash(floor(params[0].time) * 13.23) * 2.0 - 1.0,
                -1.0
            );

            float2 boltDir = normalize(boltEnd - boltStart);
            float boltLength = length(boltEnd - boltStart);

            float2 toPixel = pixelNDC - boltStart;
            float alongBolt = dot(toPixel, boltDir);
            float2 closest = boltStart + boltDir * clamp(alongBolt, 0.0, boltLength);
            float acrossBolt = length(pixelNDC - closest);

            float core = exp(-acrossBolt / LIGHTNING_BOLT_WIDTH);

            float zigzag = sin(alongBolt * LIGHTNING_ZIGZAG_FREQ
                               + params[0].time * 20.0)
                           * LIGHTNING_ZIGZAG_AMOUNT;

            float zigzagMask = exp(-abs(zigzag) * 25.0);

            float timeMask = smoothstep(0.0, 0.15, boltProgress) *
                             smoothstep(1.0, 0.7, boltProgress);

            float boltShape = core * zigzagMask * timeMask;

            col += float3(1.0, 1.0, 1.0) * boltShape * LIGHTNING_BOLT_BRIGHTNESS;
        }

    } else {
        // ========================================================================
        // ОБРАБОТКА ЦВЕТОВ ДЛЯ ВСЕХ СОСТОЯНИЙ КРОМЕ STORM
        // ========================================================================

        // КРИТИЧНО: В режиме CHAOTIC просто выводим оригинальный цвет с свечением!
        if (params[0].state == SIMULATION_STATE_CHAOTIC ||
            params[0].state == SIMULATION_STATE_COLLECTED) {
            // Берём оригинальный цвет БЕЗ каких-либо модификаций
            col = baseColor;
            
            // Только добавляем мягкое свечение
            float glow = pow(1.0 - dist, 2.5) * 0.2;
            col += float3(glow);
        } else {
            // Для других режимов используем полное освещение
            float localTime = params[0].time * getStateTimeScale(params[0].state);
            col = calculateParticle2DLighting(
                baseColor,              // Базовый цвет частицы (linear)
                in.screenPos,           // Позиция на экране
                params[0].screenSize,   // Размер экрана для NDC-освещения
                dist,                   // Расстояние от центра
                localTime,              // Адаптированное время
                params[0].state,        // Текущее состояние
                in.brightnessBoost      // Усиление яркости
            );

            // Дополнительные акценты для других состояний
            float stateEnergy = 1.0;
            float rimStrength = 0.0;

            if (params[0].state == SIMULATION_STATE_IDLE) {
                stateEnergy = 0.6;
            }

            if (params[0].state == SIMULATION_STATE_COLLECTING) {
                rimStrength = 0.25;
            }

            if (params[0].state == SIMULATION_STATE_COLLECTED) {
                stateEnergy = 1.0;
                rimStrength = 0.45;
            }

            col *= stateEnergy;

            if (rimStrength > 0.0) {
                float rim = pow(1.0 - dist, 2.0);
                col += float3(1.0, 0.9, 0.7) * rim * rimStrength;
            }
        }
    }

    // ============================================================================
    // ФИНАЛЬНАЯ ОБРАБОТКА ПРОЗРАЧНОСТИ
    // ============================================================================

    float finalAlpha;

    switch (params[0].state) {
        case SIMULATION_STATE_LIGHTNING_STORM: {
            // Буря: полная непрозрачность с контролем яркости
            finalAlpha = alpha;
            col = clamp(col, 0.0, STORM_MAX_BRIGHTNESS);
            break;
        }

        case SIMULATION_STATE_COLLECTING:
        case SIMULATION_STATE_COLLECTED: {
            // Режимы сбора: показываем все пиксели без альфа-отбраковки
            finalAlpha = 1.0;
            break;
        }

        case SIMULATION_STATE_IDLE:
        case SIMULATION_STATE_CHAOTIC:
        default: {
            // Обычные режимы: стандартное смешивание
            // Усиливаем альфа для видимости ЗДЕСЬ, в рендеринге
            // Это не искажает исходные данные в PixelCache, только визуальное отображение
            float pixelAlpha = in.color.a;
            
            // Если альфа низкая/средняя, усиливаем её для видимости
            if (pixelAlpha >= 0.1 && pixelAlpha < 0.8) {
                // Усиливаем альфа: минимум 60%, максимум 100%
                pixelAlpha = max(0.6, min(pixelAlpha * 2.0, 1.0));
            }
            
            finalAlpha = alpha * pixelAlpha;
            break;
        }
    }

    return float4(col, finalAlpha);
}

// ============================================================================
// АЛЬТЕРНАТИВНЫЙ FRAGMENT ШЕЙДЕР - РЕЖИМ ПРОИЗВОДИТЕЛЬНОСТИ
// ============================================================================
// Fast-path для будущего переключения качества. Сейчас основной pipeline его не вызывает.

/*
    УПРОЩЕННАЯ ВЕРСИЯ ДЛЯ МАКСИМАЛЬНОЙ ПРОИЗВОДИТЕЛЬНОСТИ

    Используй эту версию когда нужно быстродействие, а не красота.
    Замени fragmentParticle на fragmentParticlePerformance в pipeline.

    Минус эффекты - плюс FPS!
*/

fragment float4 fragmentParticlePerformance(
    VertexOut in [[stage_in]],
    float2 pointCoord [[point_coord]],
    constant SimulationParams * params [[buffer(1)]]
) {
    // Простая подготовка координат
    float2 uv = pointCoord * 2.0 - 1.0;
    float dist = length(uv);

    // Простая круглая форма
    // Форма частицы учитывается через dist в освещении ниже

    // МИНИМАЛЬНОЕ ОСВЕЩЕНИЕ
    float3 col;
    float3 baseColor = srgbToLinear(in.color.rgb);

    if (params[0].state == SIMULATION_STATE_LIGHTNING_STORM) {
        // Упрощенные цвета бури
        float electricSeed = dot(uv, float2(12.9898, 78.233)) + params[0].time;
        float hue = hash(electricSeed) * TWO_PI;
        col = float3(
            0.3 + 0.7 * sin(hue),
            0.4 + 0.6 * cos(hue),
            0.8
        ) * 3.0;
        float stormCore = pow(max(1.0 - dist, 0.0), 3.0);
        col += float3(0.2, 0.4, 0.7) * stormCore * STORM_CORE_SOFTNESS;
    } else {
        // Только простое свечение
        float glow = pow(1.0 - dist, 2.5) * GLOW_BASE_INTENSITY;
        col = clamp(baseColor * in.brightnessBoost, 0.0, 1.0) + glow;
    }

    float finalAlpha = 1.0;
    return float4(col, finalAlpha);
}
#endif /* Basic_h */
