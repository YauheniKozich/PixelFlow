#ifndef PixelSampler_h
#define PixelSampler_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    int x;
    int y;
    float r;
    float g;
    float b;
    float a;
} SampleC;

/// Stratified sampling по вертикали
/// samples        — входные сэмплы
/// sampleCount    — количество входных сэмплов
/// targetCount    — количество выходных сэмплов
/// imageHeight    — высота изображения
/// bands          — количество горизонтальных полос
/// outSamples     — выходной массив (должен быть size targetCount)
void stratifiedSampleC(SampleC* samples, int sampleCount, int targetCount, int imageHeight, int bands, SampleC* outSamples);

#ifdef __cplusplus
}
#endif

#endif /* PixelSampler_h */
