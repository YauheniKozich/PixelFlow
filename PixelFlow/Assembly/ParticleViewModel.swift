//
//  ParticleViewModel.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.

import UIKit
import MetalKit

// MARK: - Public Notification

extension Notification.Name {
    /// Posted when high‑quality particles have been generated and swapped
    /// for the fast‑preview particles.
    static let particleQualityUpgraded = Notification.Name("ParticleQualityUpgraded")
}

// MARK: - ParticleViewModel

/// Управляет загрузкой изображения, созданием `ParticleSystem`,
/// переключением от быстрого превью к качественным частицам,
/// обработкой low‑memory и небольшим публичным API, пригодным для unit‑тестов.
final class ParticleViewModel {
    
    // MARK: - Public read‑only state
    
    @MainActor public private(set) var isConfigured = false
    @MainActor public private(set) var isGeneratingHighQuality = false
    @MainActor public private(set) var particleSystem: ParticleSystemAdapter?
    
    // MARK: - Private storage

    private let logger: LoggerProtocol
    private let imageLoader: ImageLoaderProtocol
    private var currentConfig = ParticleGenerationConfig.standard
    private var qualityTask: Task<Void, Never>?
    private var memoryWarningObserver: NSObjectProtocol?
    
    // --------------------------------------------------------------------
    // MARK: - Life‑cycle
    
    public init(logger: LoggerProtocol = Logger.shared,
                imageLoader: ImageLoaderProtocol = ImageLoader()) {
        self.logger = logger
        self.imageLoader = imageLoader
        logger.info("ParticleViewModel init")
        observeMemoryWarnings()
    }
    
    deinit {
        self.cleanupAllResources()
        self.logger.info("ParticleViewModel deinit")
    }
    
    // --------------------------------------------------------------------
    // MARK: - Public API – Configuration
    
    @MainActor public func apply(_ newConfig: ParticleGenerationConfig) {
        currentConfig = newConfig
        logger.info("New configuration applied: \(newConfig)")
        
        // Если система уже существует – сбрасываем её,
        // чтобы при следующем `createSystem` использовалась новая конфигурация.
        if isConfigured {
            resetParticleSystem()
        }
    }
    
    @MainActor  func applyDraftPreset()   { apply(ParticleGenerationConfig.draft)   }
    @MainActor func applyStandardPreset() { apply(ParticleGenerationConfig.standard) }
    @MainActor  func applyHighPreset()    { apply(ParticleGenerationConfig.high)    }
    @MainActor func applyUltraPreset()   { apply(ParticleGenerationConfig.ultra)   }
    
    // --------------------------------------------------------------------
    // MARK: - Public API – System Lifecycle
    
    /// Создаёт и запускает `ParticleSystem` в переданном `MTKView`.
    /// Возвращает `true`, если всё прошло успешно.
    @MainActor
    public func createSystem(in view: MTKView) async -> Bool {
        guard !isConfigured else {
            logger.info("Particle system is already configured")
            return true
        }
        
        // Загрузка изображения
        logger.info("Loading source image…")
        guard let image = imageLoader.loadImageWithFallback() else {
            logger.error("Failed to load source image")
            return false
        }
        
        // Вычисление количества частиц
        let particleCount = optimalParticleCount(for: image,
                                                 preset: currentConfig.qualityPreset)
        logger.info("Calculated particle count: \(particleCount)")

        // Обновляем конфигурацию с правильным количеством частиц
        var config = currentConfig
        config.targetParticleCount = particleCount

        // Инициализация ParticleSystem через адаптер (новая архитектура).
        //    `ParticleSystemAdapter` имеет failable‑initializer → возвращает `ParticleSystemAdapter?`.
        guard let system = ParticleSystemAdapter(
            mtkView: view,
            image: image,
            particleCount: particleCount,
            config: config) else {

            logger.error("ParticleSystemAdapter initialization failed (nil returned)")
            return false
        }

        // Сохранить ссылку
        particleSystem = system

        // Быстрый превью
        system.initializeWithFastPreview()
        system.startSimulation()

        isConfigured = true
        logger.info("Particle system created – fast preview started")
        
        // Фоновая генерация качественных частиц
        startQualityGeneration(for: system)
        
        return true
    }
    
    /// Останавливает текущую систему и очищает её состояние.
    @MainActor public func resetParticleSystem() {
        logger.info("Resetting particle system")
        cancelQualityTask()
        particleSystem?.cleanup()
        particleSystem = nil
        isConfigured = false
    }
    
    /// Переключает симуляцию между паузой и запуском.
    @MainActor public func toggleSimulation() {
        guard let system = particleSystem else { return }
        if system.hasActiveSimulation {
            system.toggleState()
        } else {
            system.startSimulation()
        }
    }
    
    /// Запускает «молниеносную бурю», если движок её поддерживает.
    @MainActor public func startLightningStorm() {
        particleSystem?.startLightningStorm()
    }
    
    // --------------------------------------------------------------------
    // MARK: - Private – High‑Quality Generation
    
    /// Запускает задачу, заменяющую быстрые частицы на качественные.
    @MainActor private func startQualityGeneration(for system: ParticleSystemAdapter) {
        cancelQualityTask()
        isGeneratingHighQuality = true
        logger.info("Launching high‑quality particle generation")
        
        qualityTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 100_000_000)
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run { self?.logger.info("Generating high‑quality particles…") }
            
            // Создаем отдельную задачу для обработки синхронного колбека
            let success = await Task.detached {
                await withCheckedContinuation { continuation in
                    // Возвращаемся на главный актор для вызова системной функции
                    Task { @MainActor in
                        system.replaceWithHighQualityParticles { ok in
                            continuation.resume(returning: ok)
                        }
                    }
                }
            }.value
            
            await MainActor.run {
                self?.isGeneratingHighQuality = false
                if success {
                    self?.logger.info("High‑quality particles ready")
                    NotificationCenter.default.post(
                        name: .particleQualityUpgraded,
                        object: nil
                    )
                } else {
                    self?.logger.warning("High‑quality particle generation failed")
                }
            }
        }
    }
    
    /// Отменить фон. задачу, если она запущена.
    @MainActor private func cancelQualityTask() {
        qualityTask?.cancel()
        qualityTask = nil
        isGeneratingHighQuality = false
    }
    
    // --------------------------------------------------------------------
    // MARK: - Low‑Memory Handling
    
    private func observeMemoryWarnings() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleLowMemory()
        }
    }
    
    private func removeMemoryWarningObserver() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        memoryWarningObserver = nil
    }
    
    private func handleLowMemory() {
        logger.warning("Low‑memory warning received – cleaning up")
        DispatchQueue.global(qos: .background).async { [weak self] in
            self?.cleanupAllResources()
        }
    }
    
    // --------------------------------------------------------------------
    // MARK: - Full Cleanup
    
    public func cleanupAllResources() {
        logger.info("Performing full resource cleanup")
        
        cancelQualityTask()
        particleSystem?.cleanup()
        particleSystem = nil
        isConfigured = false
        
        // Простая очистка кеша – НЕ заменяем глобальный URLCache.
        URLCache.shared.removeAllCachedResponses()
        clearTemporaryDirectory()
        removeMemoryWarningObserver()
        
        logger.info("All resources released")
    }
    
    private func clearTemporaryDirectory() {
        let tmp = FileManager.default.temporaryDirectory
        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: tmp,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            for url in entries where url.lastPathComponent.hasPrefix("ParticleCache_") {
                try? FileManager.default.removeItem(at: url)
            }
        } catch {
            logger.debug("Failed to clear temporary directory: \(error)")
        }
    }
    
    // --------------------------------------------------------------------
    // MARK: - Image Loading
    
    private func loadImage() -> CGImage? {
        let possibleNames = ["steve", "test", "image"]
        for name in possibleNames {
            if let ui = UIImage(named: name) {
                logger.info("Loaded bundled image ‘\(name)’ – \(ui.size.width)x\(ui.size.height) pts")
                return ui.cgImage
            }
        }
        logger.info("No bundled image found – generating test pattern")
        return createTestImage()
    }
    
    private func createTestImage() -> CGImage? {
        let size = CGSize(width: 512, height: 512)
        let renderer = UIGraphicsImageRenderer(size: size)
        
        let ui = renderer.image { ctx in
            // Gradient background
            if let gradient = CGGradient(
                colorsSpace: CGColorSpaceCreateDeviceRGB(),
                colors: [UIColor.systemBlue.cgColor,
                         UIColor.systemPurple.cgColor] as CFArray,
                locations: [0, 1]) {
                
                ctx.cgContext.drawLinearGradient(
                    gradient,
                    start: .zero,
                    end: CGPoint(x: size.width, y: size.height),
                    options: []
                )
            }
            
            // White outer circle
            UIColor.white.setFill()
            UIBezierPath(
                ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 100, dy: 100)
            ).fill()
            
            // Black inner circle
            UIColor.black.setFill()
            UIBezierPath(
                ovalIn: CGRect(origin: .zero, size: size).insetBy(dx: 200, dy: 200)
            ).fill()
        }
        
        return ui.cgImage
    }
    
    // --------------------------------------------------------------------
    // MARK: - Particle Count & Config Helpers
    
    /// Вычисляет количество частиц, учитывая плотность, зависящую от `QualityPreset`.
    private func optimalParticleCount(for image: CGImage,
                                      preset: QualityPreset) -> Int {
        let pixelCount = Float(image.width * image.height)
        
        // Плотности подобраны экспериментально.
        let density: Float
        switch preset {
        case .draft:   density = 0.00004   // ≈ 4 % от 4K‑изображения
        case .standard: density = 0.00008
        case .high:    density = 0.00012
        case .ultra:   density = 0.00020
        }
        
        let raw = Int(pixelCount * density)
        let clamped = max(10_000, min(raw, 300_000))
        
        logger.info("optimalParticleCount – raw:\(raw) clamped:\(clamped) for preset:\(preset)")
        return clamped
    }
    
    // --------------------------------------------------------------------
    // MARK: - Debug / Diagnostics
    
    @MainActor public func configurationInfo() -> String {
        let status = isGeneratingHighQuality ? "Generating…" :
        (particleSystem?.isHighQuality ?? false ? "High‑quality" : "Fast preview")
        return """
        === ParticleViewModel ===
        Config preset      : \(currentConfig.qualityPreset)
        Sampling algorithm : \(currentConfig.samplingStrategy)
        Particle count    : \(particleSystem?.particleCount ?? 0)
        Status            : \(status)
        Caching           : \(currentConfig.enableCaching ? "ON" : "OFF")
        SIMD              : \(currentConfig.useSIMD ? "ON" : "OFF")
        Concurrent ops    : \(currentConfig.maxConcurrentOperations)
        Cache limit (MB)  : \(currentConfig.cacheSizeLimit)
        Particle size     : \(currentConfig.minParticleSize) – \(currentConfig.maxParticleSize)
        Importance thresh : \(String(format: "%.2f", currentConfig.importanceThreshold))
        Contrast weight   : \(String(format: "%.2f", currentConfig.contrastWeight))
        Saturation weight : \(String(format: "%.2f", currentConfig.saturationWeight))
        Edge radius       : \(currentConfig.edgeDetectionRadius)
        """
    }
    
    @MainActor public func logCurrentConfiguration() {
        logger.info("=== Current Particle Configuration ===")
        logger.info("Preset                : \(currentConfig.qualityPreset)")
        logger.info("Sampling strategy     : \(currentConfig.samplingStrategy)")
        logger.info("Particle count        : \(particleSystem?.particleCount ?? 0)")
        logger.info("High‑quality active   : \(particleSystem?.isHighQuality ?? false)")
        logger.info("Generating HQ         : \(isGeneratingHighQuality)")
        logger.info("====================================")
    }
}
