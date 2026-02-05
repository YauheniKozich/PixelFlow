//
//  GenerationContext.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Контекст генерации частиц - хранилище состояния
//

import CoreGraphics
import Foundation

/// Контекст генерации частиц - потокобезопасное хранилище состояния
final class GenerationContext: GenerationContextProtocol {

    // MARK: - Properties

    private let stateQueue = DispatchQueue(label: "com.generation.context", attributes: .concurrent)

    private var _image: CGImage?
    private var _config: ParticleGenerationConfig?
    private var _targetParticleCount: Int = 0
    private var _isCancelled: Bool = false
    private var _analysis: ImageAnalysis?
    private var _samples: [Sample] = []
    private var _particles: [Particle] = []
    private var _progress: Float = 0.0
    private var _currentStage: String = "Idle"

    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(logger: LoggerProtocol) {
        self.logger = logger
        logger.info("GenerationContext initialized")
    }

    // MARK: - GenerationContextProtocol

    var image: CGImage? {
        get { stateQueue.sync { _image } }
        set {
            stateQueue.async(flags: .barrier) {
                self._image = newValue
                if let image = newValue {
                    self.logger.debug("Image set in context: \(image.width)x\(image.height)")
                }
            }
        }
    }

    var config: ParticleGenerationConfig? {
        get { stateQueue.sync { _config } }
        set { stateQueue.async(flags: .barrier) { self._config = newValue } }
    }

    var targetParticleCount: Int {
        get { stateQueue.sync { _targetParticleCount } }
        set { stateQueue.async(flags: .barrier) { self._targetParticleCount = newValue } }
    }

    var isCancelled: Bool {
        get { stateQueue.sync { _isCancelled } }
        set { stateQueue.async(flags: .barrier) { self._isCancelled = newValue } }
    }

    var analysis: ImageAnalysis? {
        get { stateQueue.sync { _analysis } }
        set { stateQueue.async(flags: .barrier) { self._analysis = newValue } }
    }

    var samples: [Sample] {
        get { stateQueue.sync { _samples } }
        set { stateQueue.async(flags: .barrier) { self._samples = newValue } }
    }

    var particles: [Particle] {
        get { stateQueue.sync { _particles } }
        set { stateQueue.async(flags: .barrier) { self._particles = newValue } }
    }

    var progress: Float {
        get { stateQueue.sync { _progress } }
        set { stateQueue.async(flags: .barrier) { self._progress = newValue } }
    }

    var currentStage: String {
        get { stateQueue.sync { _currentStage } }
        set { stateQueue.async(flags: .barrier) { self._currentStage = newValue } }
    }

    func reset() {
        stateQueue.async(flags: .barrier) {
            self._image = nil
            self._config = nil
            self._targetParticleCount = 0
            self._isCancelled = false
            self._analysis = nil
            self._samples.removeAll()
            self._particles.removeAll()
            self._progress = 0.0
            self._currentStage = "Idle"
        }
        logger.debug("GenerationContext reset")
    }

    func updateProgress(_ progress: Float, stage: String) {
        stateQueue.async(flags: .barrier) {
            self._progress = progress
            self._currentStage = stage
        }
        logger.debug("Progress updated: \(progress) - \(stage)")
    }

    // MARK: - Additional Methods

    /// Проверяет готовность контекста для указанного этапа
    func isReadyForStage(_ stage: GenerationStage) -> Bool {
        stateQueue.sync {
            switch stage {
            case .analysis:
                return _image != nil
            case .sampling:
                return _image != nil && _analysis != nil
            case .assembly:
                return _image != nil && _analysis != nil && !_samples.isEmpty
            case .caching:
                return !_particles.isEmpty
            }
        }
    }

    /// Получает статистику генерации
    func generationStats() -> GenerationStats {
        stateQueue.sync {
            GenerationStats(
                imageSize: _image.map { "\($0.width)x\($0.height)" } ?? "N/A",
                sampleCount: _samples.count,
                particleCount: _particles.count,
                progress: _progress,
                currentStage: _currentStage
            )
        }
    }
}

/// Статистика генерации
struct GenerationStats {
    let imageSize: String
    let sampleCount: Int
    let particleCount: Int
    let progress: Float
    let currentStage: String

    var description: String {
        """
        Image: \(imageSize)
        Samples: \(sampleCount)
        Particles: \(particleCount)
        Progress: \(String(format: "%.1f%%", progress * 100))
        Stage: \(currentStage)
        """
    }
}
