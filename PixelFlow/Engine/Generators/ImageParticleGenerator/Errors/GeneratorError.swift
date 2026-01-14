//
//  GeneratorError.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 14.01.26.
//

import Foundation

enum GeneratorError: LocalizedError {
    case invalidImage
    case invalidParticleCount
    case analysisFailed(reason: String)
    case samplingFailed(reason: String)
    case assemblyFailed(reason: String)
    case stageFailed(stage: String, error: Error)
    case cacheError(reason: String)
    case cancelled
    
    var errorDescription: String? {
        switch self {
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
        }
    }
}
