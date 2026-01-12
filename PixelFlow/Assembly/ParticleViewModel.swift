//
//  ParticleViewModel.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import UIKit
import MetalKit

class ParticleViewModel {
    // MARK: - Public Properties
    private(set) var particleSystem: ParticleSystem?
    private(set) var isConfigured = false

    // MARK: - Configuration Properties
    private(set) var currentSamplingAlgorithm: SamplingAlgorithm = .uniform
    private(set) var currentQualityPreset: QualityPreset = .standard
    private(set) var currentEnableCaching: Bool = true
    private(set) var currentMaxConcurrentOperations: Int = ProcessInfo.processInfo.activeProcessorCount
    private(set) var currentImportanceThreshold: Float = 0.25
    private(set) var currentContrastWeight: Float = 0.5
    private(set) var currentSaturationWeight: Float = 0.3
    private(set) var currentEdgeDetectionRadius: Int = 2
    private(set) var currentMinParticleSize: Float = 2.0
    private(set) var currentMaxParticleSize: Float = 7.0
    private(set) var currentUseSIMD: Bool = true
    private(set) var currentCacheSizeLimit: Int = 100
    private(set) var currentParticleCount: Int = 35000

    // MARK: - Private Properties
    private let logger = Logger.shared

    // MARK: - Initialization
    init() {
        logger.info("ParticleViewModel initialized")
    }

    // MARK: - Public Methods

    func setupParticleSystem(with mtkView: MTKView, screenSize: CGSize) -> Bool {
        guard !isConfigured else {
            logger.warning("Система частиц уже настроена")
            return true
        }

        logger.info("Настройка системы частиц с оптимизированной конфигурацией")

        // Очищаем кэш для применения новых настроек
        clearParticleCache()

        guard let image = loadImage() else {
            logger.error("Не удалось загрузить изображение для системы частиц")
            return false
        }

        logger.info("Изображение успешно загружено: \(image.width) x \(image.height)")
        let particleCount = determineOptimalParticleCount()
        let config = createOptimalConfig()
        logger.info("Используется \(particleCount) частиц с оптимизированной конфигурацией")

        // Создать ParticleSystem с оптимизированной конфигурацией
        particleSystem = ParticleSystem(
            mtkView: mtkView,
            image: image,
            particleCount: particleCount,
            config: config
        )

        guard particleSystem != nil else {
            logger.error("Не удалось создать систему частиц")
            return false
        }

        // Настроить и инициализировать простыми частицами (быстро)
        particleSystem?.configure(screenSize: screenSize)
        particleSystem?.initializeWithSimpleParticles()
        particleSystem?.startSimulation()

        isConfigured = true
        logger.info("Система частиц инициализирована простыми частицами и запущена")
        logGestureInstructions()

        // Заменить на реальные частицы асинхронно
        particleSystem?.replaceParticlesAsync { success in
            if success {
                self.logger.info("Успешно заменены простые частицы на сгенерированные")
            } else {
                self.logger.warning("Не удалось заменить частицы, оставлены простые")
            }
        }

        return true
    }

    func resetParticleSystem() {
        logger.info("Сброс системы частиц")
        particleSystem = nil
        isConfigured = false
    }

    func handleSingleTap() {
        guard let particleSystem = particleSystem else { return }

        if particleSystem.hasActiveSimulation {
            particleSystem.toggleState()
        } else {
            particleSystem.startSimulation()
        }
    }

    func handleDoubleTap() {
        logger.info("Двойное нажатие: сброс системы")
        resetParticleSystem()
    }

    func handleTripleTap() {
        logger.info("Тройное нажатие: запуск грозы")
        particleSystem?.startLightningStorm()
    }

    // MARK: - Configuration Methods

    /// Установить алгоритм сэмплинга
    func setSamplingAlgorithm(_ algorithm: SamplingAlgorithm) {
        currentSamplingAlgorithm = algorithm
        logger.info("Алгоритм сэмплинга изменен на: \(algorithm)")
        applyConfigurationChanges()
    }

    /// Установить preset качества
    func setQualityPreset(_ preset: QualityPreset) {
        currentQualityPreset = preset
        logger.info("Пресет качества изменен на: \(preset)")
        applyConfigurationChanges()
    }

    /// Включить/выключить кэширование
    func setCachingEnabled(_ enabled: Bool) {
        currentEnableCaching = enabled
        logger.info("Кэширование \(enabled ? "включено" : "отключено")")
        applyConfigurationChanges()
    }

    /// Установить максимальное количество одновременных операций
    func setMaxConcurrentOperations(_ count: Int) {
        let clamped = max(1, min(count, ProcessInfo.processInfo.activeProcessorCount * 2))
        currentMaxConcurrentOperations = clamped
        logger.info("Максимальное количество одновременных операций установлено на: \(clamped)")
        applyConfigurationChanges()
    }

    /// Установить порог важности пикселей (0.0 - 1.0)
    func setImportanceThreshold(_ threshold: Float) {
        currentImportanceThreshold = max(0.0, min(1.0, threshold))
        logger.info("Importance threshold set to: \(String(format: "%.2f", currentImportanceThreshold))")
        applyConfigurationChanges()
    }

    /// Установить вес контраста (0.0 - 2.0)
    func setContrastWeight(_ weight: Float) {
        currentContrastWeight = max(0.0, min(2.0, weight))
        logger.info("Contrast weight set to: \(String(format: "%.2f", currentContrastWeight))")
        applyConfigurationChanges()
    }

    /// Установить вес насыщенности (0.0 - 2.0)
    func setSaturationWeight(_ weight: Float) {
        currentSaturationWeight = max(0.0, min(2.0, weight))
        logger.info("Saturation weight set to: \(String(format: "%.2f", currentSaturationWeight))")
        applyConfigurationChanges()
    }

    /// Установить радиус обнаружения краев (1 - 5)
    func setEdgeDetectionRadius(_ radius: Int) {
        currentEdgeDetectionRadius = max(1, min(5, radius))
        logger.info("Edge detection radius set to: \(currentEdgeDetectionRadius)")
        applyConfigurationChanges()
    }

    /// Установить минимальный размер частиц (0.5 - 5.0)
    func setMinParticleSize(_ size: Float) {
        let clamped = max(0.5, min(5.0, size))
        currentMinParticleSize = min(clamped, currentMaxParticleSize - 0.5) // Не больше max
        logger.info("Min particle size set to: \(String(format: "%.1f", currentMinParticleSize))")
        applyConfigurationChanges()
    }

    /// Установить максимальный размер частиц (1.0 - 20.0)
    func setMaxParticleSize(_ size: Float) {
        let clamped = max(1.0, min(20.0, size))
        currentMaxParticleSize = max(clamped, currentMinParticleSize + 0.5) // Не меньше min
        logger.info("Max particle size set to: \(String(format: "%.1f", currentMaxParticleSize))")
        applyConfigurationChanges()
    }

    /// Включить/выключить SIMD оптимизации
    func setSIMDEnabled(_ enabled: Bool) {
        currentUseSIMD = enabled
        logger.info("SIMD \(enabled ? "включен" : "отключен")")
        applyConfigurationChanges()
    }

    /// Установить лимит размера кэша в MB (10 - 1000)
    func setCacheSizeLimit(_ limit: Int) {
        currentCacheSizeLimit = max(10, min(1000, limit))
        logger.info("Cache size limit set to: \(currentCacheSizeLimit) MB")
        applyConfigurationChanges()
    }

    /// Установить количество частиц (1000 - 100000)
    func setParticleCount(_ count: Int) {
        currentParticleCount = max(1000, min(100000, count))
        logger.info("Particle count set to: \(currentParticleCount)")
        applyConfigurationChanges()
    }

    /// Получить текущую конфигурацию
    func getCurrentConfig() -> ParticleGenerationConfig {
        return ParticleGenerationConfig(
            samplingStrategy: .advanced(currentSamplingAlgorithm),
            qualityPreset: currentQualityPreset,
            enableCaching: currentEnableCaching,
            maxConcurrentOperations: currentMaxConcurrentOperations,
            importanceThreshold: currentImportanceThreshold,
            contrastWeight: currentContrastWeight,
            saturationWeight: currentSaturationWeight,
            edgeDetectionRadius: currentEdgeDetectionRadius,
            minParticleSize: currentMinParticleSize,
            maxParticleSize: currentMaxParticleSize,
            useSIMD: currentUseSIMD,
            cacheSizeLimit: currentCacheSizeLimit
        )
    }

    /// Применить изменения конфигурации (пересоздать систему частиц)
    private func applyConfigurationChanges() {
        guard isConfigured else {
            logger.debug("Configuration changed but system not initialized yet")
            return
        }

        logger.info("Applying configuration changes...")

        // Остановить текущую систему
        particleSystem = nil
        isConfigured = false

        // Переинициализировать с новыми настройками
        // Это будет вызвано автоматически через viewDidLayoutSubviews
        DispatchQueue.main.async {
            if let window = UIApplication.shared.windows.first,
               let rootVC = window.rootViewController as? ViewController {
                rootVC.view.setNeedsLayout()
            }
        }
    }

    // MARK: - Preset Configurations

    /// Установить конфигурацию для быстрой разработки (draft)
    func setDraftConfiguration() {
        currentSamplingAlgorithm = .hashBased
        currentQualityPreset = .draft
        currentEnableCaching = false
        currentMaxConcurrentOperations = 2
        currentImportanceThreshold = 0.1
        currentContrastWeight = 0.2
        currentSaturationWeight = 0.1
        currentEdgeDetectionRadius = 1
        currentMinParticleSize = 3.0
        currentMaxParticleSize = 6.0
        currentUseSIMD = false
        currentCacheSizeLimit = 10
        currentParticleCount = 10000

        logger.info("Применена черновая конфигурация (быстрая разработка)")
        applyConfigurationChanges()
    }

    /// Установить стандартную конфигурацию
    func setStandardConfiguration() {
        currentSamplingAlgorithm = .blueNoise
        currentQualityPreset = .standard
        currentEnableCaching = true
        currentMaxConcurrentOperations = ProcessInfo.processInfo.activeProcessorCount
        currentImportanceThreshold = 0.25
        currentContrastWeight = 0.5
        currentSaturationWeight = 0.3
        currentEdgeDetectionRadius = 2
        currentMinParticleSize = 2.0
        currentMaxParticleSize = 7.0
        currentUseSIMD = true
        currentCacheSizeLimit = 100
        currentParticleCount = 35000

        logger.info("Применена стандартная конфигурация (баланс качества/скорости)")
        applyConfigurationChanges()
    }

    /// Установить высококачественную конфигурацию
    func setHighQualityConfiguration() {
        currentSamplingAlgorithm = .blueNoise
        currentQualityPreset = .ultra
        currentEnableCaching = true
        currentMaxConcurrentOperations = ProcessInfo.processInfo.activeProcessorCount * 2
        currentImportanceThreshold = 0.5
        currentContrastWeight = 0.5
        currentSaturationWeight = 0.4
        currentEdgeDetectionRadius = 3
        currentMinParticleSize = 1.0
        currentMaxParticleSize = 12.0
        currentUseSIMD = true
        currentCacheSizeLimit = 500
        currentParticleCount = 50000

        logger.info("Применена высококачественная конфигурация (максимальное качество)")
        applyConfigurationChanges()
    }

    /// Сбросить к настройкам по умолчанию
    func resetToDefaults() {
        setStandardConfiguration()
    }

    // MARK: - Debug & Info Methods

    /// Получить информацию о текущих настройках
    func getConfigurationInfo() -> String {
        return """
        Current Configuration:
        - Algorithm: \(currentSamplingAlgorithm)
        - Quality: \(currentQualityPreset)
        - Particles: \(currentParticleCount)
        - Caching: \(currentEnableCaching ? "ON" : "OFF")
        - SIMD: \(currentUseSIMD ? "ON" : "OFF")
        - Concurrent Ops: \(currentMaxConcurrentOperations)
        - Cache Limit: \(currentCacheSizeLimit)MB
        - Particle Size: \(String(format: "%.1f", currentMinParticleSize)) - \(String(format: "%.1f", currentMaxParticleSize))
        - Importance Threshold: \(String(format: "%.2f", currentImportanceThreshold))
        - Contrast Weight: \(String(format: "%.2f", currentContrastWeight))
        - Saturation Weight: \(String(format: "%.2f", currentSaturationWeight))
        - Edge Detection Radius: \(currentEdgeDetectionRadius)
        """
    }

    /// Логировать текущие настройки
    func logCurrentConfiguration() {
        logger.info("=== Current Configuration ===")
        logger.info("Algorithm: \(currentSamplingAlgorithm)")
        logger.info("Quality: \(currentQualityPreset)")
        logger.info("Particles: \(currentParticleCount)")
        logger.info("Caching: \(currentEnableCaching)")
        logger.info("SIMD: \(currentUseSIMD)")
        logger.info("Size range: \(currentMinParticleSize)-\(currentMaxParticleSize)")
        logger.info("=============================")
    }

    // MARK: - Quick Algorithm Switching

    /// Переключиться на Blue Noise (оптимальное качество)
    func switchToBlueNoise() {
        setSamplingAlgorithm(.blueNoise)
    }

    /// Переключиться на Hash-Based (максимальная скорость)
    func switchToHashBased() {
        setSamplingAlgorithm(.hashBased)
    }

    /// Переключиться на Uniform (классический)
    func switchToUniform() {
        setSamplingAlgorithm(.uniform)
    }

    /// Переключиться на Van der Corput (математическая точность)
    func switchToVanDerCorput() {
        setSamplingAlgorithm(.vanDerCorput)
    }

    /// Переключиться на Adaptive (учитывает цвета)
    func switchToAdaptive() {
        setSamplingAlgorithm(.adaptive)
    }

    // MARK: - Quality Presets

    /// Переключиться на draft качество
    func switchToDraftQuality() {
        setQualityPreset(.draft)
    }

    /// Переключиться на standard качество
    func switchToStandardQuality() {
        setQualityPreset(.standard)
    }

    /// Переключиться на high качество
    func switchToHighQuality() {
        setQualityPreset(.high)
    }

    /// Переключиться на ultra качество
    func switchToUltraQuality() {
        setQualityPreset(.ultra)
    }

    private func clearParticleCache() {
        // Кэш очищается автоматически в ImageParticleGenerator при новой конфигурации
        logger.debug("Particle cache cleared via ImageParticleGenerator")
    }

    // MARK: - Private Methods

    private func loadImage() -> CGImage? {
        logger.info("Загрузка изображения...")

        // Попробовать разные имена изображений
        let imageNames = ["steve", "test", "image"]

        for name in imageNames {
            if let uiImage = UIImage(named: name) {
                logger.info("Загружено изображение: \(name) - \(uiImage.size.width) x \(uiImage.size.height)")
                return uiImage.cgImage
            }
        }

        logger.info("Ресурсы не найдены, создается тестовое изображение")
        return createTestImage()
    }

    private func createTestImage() -> CGImage? {
        let size = CGSize(width: 512, height: 512)

        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let bounds = CGRect(origin: .zero, size: size)

            // Градиентный фон
            if let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                                        colors: [UIColor.systemBlue.cgColor, UIColor.systemPurple.cgColor] as CFArray,
                                        locations: [0, 1]) {
                context.cgContext.drawLinearGradient(gradient,
                                                    start: CGPoint(x: 0, y: 0),
                                                    end: CGPoint(x: size.width, y: size.height),
                                                    options: [])
            }

            // Контрастная фигура
            UIColor.white.setFill()
            let circlePath = UIBezierPath(ovalIn: bounds.insetBy(dx: 100, dy: 100))
            circlePath.fill()

            UIColor.black.setFill()
            let innerCircle = UIBezierPath(ovalIn: bounds.insetBy(dx: 200, dy: 200))
            innerCircle.fill()
        }

        return image.cgImage
    }

    private func determineOptimalParticleCount() -> Int {
        return currentParticleCount
    }

    private func createOptimalConfig() -> ParticleGenerationConfig {
        return getCurrentConfig()
    }

    private func logGestureInstructions() {
        logger.info("👆 1 finger: control states")
        logger.info("👆👆 2 fingers: reset system")
        logger.info("👆👆👆 3 fingers: lightning storm")
    }
}
