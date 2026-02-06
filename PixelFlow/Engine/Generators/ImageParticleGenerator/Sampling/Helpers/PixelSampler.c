//
//  PixelSampler.c
//  PixelFlow
//
//  Created by Yauheni Kozich on 15.01.26.
//

#include "PixelSampler.h"

#include <stdlib.h>
#include <stdint.h>
#include <math.h>


/// Stratified sampling по вертикали
/// samples        — входные сэмплы
/// sampleCount    — их количество
/// targetCount    — сколько хотим получить
/// imageHeight    — высота изображения
/// bands          — на сколько полос делим
/// outSamples     — выходной массив (должен быть targetCount)
void stratifiedSampleC(SampleC* samples, int sampleCount, int targetCount, int imageHeight, int bands, SampleC* outSamples) {
    if (!samples || sampleCount <= 0 || targetCount <= 0 || !outSamples) return;
    if (bands <= 0 || imageHeight <= 0) return;

    int bandHeight = (imageHeight + bands - 1) / bands;

    // Массивы для каждой полосы
    SampleC** buckets = (SampleC**)calloc(bands, sizeof(SampleC*));
    float* bucketImportance = (float*)calloc(bands, sizeof(float));
    int* bucketSizes = (int*)calloc(bands, sizeof(int));
    int* bucketCaps = (int*)calloc(bands, sizeof(int));

    for (int i = 0; i < bands; i++) {
        bucketCaps[i] = 64;
        buckets[i] = (SampleC*)malloc(bucketCaps[i] * sizeof(SampleC));
    }

    // Распределяем сэмплы по полосам и считаем «важность» каждого
    float totalImportance = 0.0f;
    for (int i = 0; i < sampleCount; i++) {
        SampleC s = samples[i];
        int band = s.y / bandHeight;
        if (band >= bands) band = bands - 1;

        // Простейшая важность: alpha * яркость
        float brightness = (s.r + s.g + s.b) / 3.0f;
        float importance = s.a * brightness;
        bucketImportance[band] += importance;
        totalImportance += importance;

        if (bucketSizes[band] >= bucketCaps[band]) {
            bucketCaps[band] *= 2;
            SampleC* tmp = (SampleC*)realloc(buckets[band], bucketCaps[band] * sizeof(SampleC));
            if (tmp) buckets[band] = tmp;
            else {
                for (int k = 0; k < bands; k++) free(buckets[k]);
                free(buckets);
                free(bucketSizes);
                free(bucketCaps);
                free(bucketImportance);
                return;
            }
        }
        buckets[band][bucketSizes[band]++] = s;
    }

    // Распределяем targetCount по полосам пропорционально важности
    int assigned = 0;
    int* quota = (int*)calloc(bands, sizeof(int));
    if (totalImportance <= 0.0f) {
        totalImportance = 0.0f;
        for (int i = 0; i < bands; i++) {
            bucketImportance[i] = (float)bucketSizes[i];
            totalImportance += bucketImportance[i];
        }
    }
    if (totalImportance <= 0.0f) {
        for (int i = 0; i < bands; i++) free(buckets[i]);
        free(buckets);
        free(bucketSizes);
        free(bucketCaps);
        free(bucketImportance);
        free(quota);
        return;
    }
    for (int i = 0; i < bands; i++) {
        quota[i] = (int)((bucketImportance[i] / totalImportance) * targetCount);
        assigned += quota[i];
    }
    // Добавляем оставшиеся сэмплы в полосы с наибольшей важностью
    while (assigned < targetCount) {
        int maxBand = 0;
        float maxImp = 0.0f;
        for (int i = 0; i < bands; i++) {
            if (bucketImportance[i] > maxImp) {
                maxImp = bucketImportance[i];
                maxBand = i;
            }
        }
        quota[maxBand]++;
        bucketImportance[maxBand] = 0.0f; // чтобы не добавлять несколько раз
        assigned++;
    }

    // Выбираем сэмплы из каждой полосы по importance
    int outIndex = 0;
    for (int i = 0; i < bands; i++) {
        int count = bucketSizes[i];
        if (count == 0 || quota[i] == 0) continue;

        // Простая выборка: сортировка по яркости * alpha
        // bubble sort для простоты (можно заменить на qsort)
        for (int j = 0; j < count-1; j++) {
            for (int k = 0; k < count-1-j; k++) {
                float imp1 = buckets[i][k].a * (buckets[i][k].r + buckets[i][k].g + buckets[i][k].b)/3.0f;
                float imp2 = buckets[i][k+1].a * (buckets[i][k+1].r + buckets[i][k+1].g + buckets[i][k+1].b)/3.0f;
                if (imp1 < imp2) {
                    SampleC tmp = buckets[i][k];
                    buckets[i][k] = buckets[i][k+1];
                    buckets[i][k+1] = tmp;
                }
            }
        }

        int step = (count / quota[i]) > 0 ? (count / quota[i]) : 1;
        for (int j = 0; j < count && outIndex < targetCount; j += step) {
            outSamples[outIndex++] = buckets[i][j];
        }
    }

// Второй проход: добираем недостающие сэмплы, если targetCount не достигнут
if (outIndex < targetCount) {
    for (int i = 0; i < bands; i++) {
        int count = bucketSizes[i];
        if (count == 0) continue;
        for (int j = 0; j < count && outIndex < targetCount; j++) {
            // проверяем, чтобы не дублировать уже выбранные сэмплы
            int alreadyUsed = 0;
            for (int k = 0; k < outIndex; k++) {
                if (outSamples[k].x == buckets[i][j].x &&
                    outSamples[k].y == buckets[i][j].y) {
                    alreadyUsed = 1;
                    break;
                }
            }
            if (!alreadyUsed) {
                outSamples[outIndex++] = buckets[i][j];
            }
        }
        if (outIndex >= targetCount) break;
    }
}

    // Освобождаем память
    for (int i = 0; i < bands; i++) free(buckets[i]);
    free(buckets);
    free(bucketSizes);
    free(bucketCaps);
    free(bucketImportance);
    free(quota);
}
