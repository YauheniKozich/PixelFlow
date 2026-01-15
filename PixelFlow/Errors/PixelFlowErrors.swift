//
//  PixelFlowErrors.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 14.01.26.
//

import Foundation

/// Объединенный enum всех ошибок в приложении PixelFlow
enum PixelFlowError: LocalizedError {
    // Generator Errors
    case invalidImage
    case invalidParticleCount
    case analysisFailed(reason: String)
    case samplingFailed(reason: String)
    case assemblyFailed(reason: String)
    case stageFailed(stage: String, error: Error)
    case cacheError(reason: String)
    case cancelled

    // Metal Errors
    case libraryCreationFailed
    case functionNotFound(name: String)
    case bufferCreationFailed
    case pipelineCreationFailed

    // Sampling Errors
    case cacheCreationFailed(underlying: Error)
    case invalidConfiguration
    case insufficientSamples
    case invalidImageDimensions

    // Pipeline Errors
    case invalidInput
    case invalidContext
    case pipelineInvalidConfiguration
    case missingImage
    case missingAnalysis
    case missingSamples
    case missingParticles
    case invalidOutput
    case emptyResult

    // Operation Errors
    case operationCancelled
    case operationTimeout
    case operationUnknown

    // Image Loader Errors
    case invalidImageData
    case imageLoaderNetworkError(Error)

    // Validation Errors
    case validationInvalidParticleCount(String)
    case validationInvalidScreenSize(String)
    case validationInvalidImage(String)

    // Parallel Strategy Errors
    case insufficientConcurrency

    var errorDescription: String? {
        switch self {
        // Generator
        case .invalidImage:
            return "Некорректное изображение"
        case .invalidParticleCount:
            return "Некорректное количество частиц"
        case .analysisFailed(let reason):
            return "Ошибка анализа: \(reason)"
        case .samplingFailed(let reason):
            return "Ошибка сэмплинга: \(reason)"
        case .assemblyFailed(let reason):
            return "Ошибка сборки частиц: \(reason)"
        case .stageFailed(let stage, let error):
            return "Ошибка этапа '\(stage)': \(error.localizedDescription)"
        case .cacheError(let reason):
            return "Ошибка кэша: \(reason)"
        case .cancelled:
            return "Операция отменена"

        // Metal
        case .libraryCreationFailed:
            return "Не удалось создать Metal библиотеку"
        case .functionNotFound(let name):
            return "Функция Metal не найдена: \(name)"
        case .bufferCreationFailed:
            return "Не удалось создать буферы Metal"
        case .pipelineCreationFailed:
            return "Не удалось создать pipeline Metal"

        // Sampling
        case .cacheCreationFailed(let underlying):
            return "Не удалось создать кэш: \(underlying.localizedDescription)"
        case .invalidConfiguration:
            return "Некорректная конфигурация сэмплинга"
        case .insufficientSamples:
            return "Недостаточно образцов"
        case .invalidImageDimensions:
            return "Некорректные размеры изображения: ширина и высота должны быть положительными"

        // Pipeline
        case .invalidInput:
            return "Некорректный ввод для pipeline"
        case .invalidContext:
            return "Некорректный контекст pipeline"
        case .pipelineInvalidConfiguration:
            return "Некорректная конфигурация pipeline"
        case .missingImage:
            return "Отсутствует изображение"
        case .missingAnalysis:
            return "Отсутствует анализ"
        case .missingSamples:
            return "Отсутствуют образцы"
        case .missingParticles:
            return "Отсутствуют частицы"
        case .invalidOutput:
            return "Некорректный вывод pipeline"
        case .emptyResult:
            return "Пустой результат генерации"

        // Operation
        case .operationCancelled:
            return "Операция отменена"
        case .operationTimeout:
            return "Превышено время ожидания операции"
        case .operationUnknown:
            return "Неизвестная ошибка операции"

        // Image Loader
        case .invalidImageData:
            return "Некорректные данные изображения"
        case .imageLoaderNetworkError(let error):
            return "Ошибка сети: \(error.localizedDescription)"

        // Validation
        case .validationInvalidParticleCount(let message):
            return message
        case .validationInvalidScreenSize(let message):
            return message
        case .validationInvalidImage(let message):
            return message

        // Parallel Strategy
        case .insufficientConcurrency:
            return "Недостаточный уровень параллелизма"
        }
    }
}

// Type aliases for backward compatibility during migration
typealias GeneratorError = PixelFlowError
typealias MetalError = PixelFlowError
typealias SamplingError = PixelFlowError
typealias GenerationPipelineError = PixelFlowError
typealias OperationError = PixelFlowError
typealias ImageLoaderError = PixelFlowError
typealias ValidationError = PixelFlowError
typealias ParallelStrategyError = PixelFlowError

