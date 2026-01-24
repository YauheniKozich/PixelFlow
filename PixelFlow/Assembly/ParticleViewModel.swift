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
    static let particleLoadFailed = Notification.Name("ParticleLoadFailed")
}

// MARK: - ParticleViewModel

/// Управляет загрузкой изображения, созданием `ParticleSystem`,
/// переключением от быстрого превью к качественным частицам,
/// обработкой low‑memory и небольшим публичным API, пригодным для unit‑тестов.
final class ParticleViewModel {
    
    // MARK: - Public read‑only state
    
    @MainActor public private(set) var isConfigured = false
    public private(set) var isGeneratingHighQuality = false
    @MainActor public private(set) var particleSystem: ParticleSystemCoordinator?
    
    // MARK: - Private storage
    
    private let logger: LoggerProtocol
    private let imageLoader: ImageLoaderProtocol
    private var currentConfig = ParticleGenerationConfig.standard
    private var qualityTask: Task<Void, Never>?
    private var memoryWarningObserver: NSObjectProtocol?
    
    // --------------------------------------------------------------------
    // MARK: - Life‑cycle
    
    public init(logger: LoggerProtocol, imageLoader: ImageLoaderProtocol) {
        self.logger = logger
        self.imageLoader = imageLoader
        logger.info("ParticleViewModel init")
        observeMemoryWarnings()
    }
    
    deinit {
        cancelQualityTask()
        particleSystem = nil
        removeMemoryWarningObserver()
        logger.info("ParticleViewModel deinit")
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
            NotificationCenter.default.post(
                name: .particleLoadFailed,
                object: nil
            )
            return false
        }
        
        // Вычисление количества частиц
        let particleCount = optimalParticleCount(for: image,
                                                 preset: currentConfig.qualityPreset)
        logger.info("Calculated particle count: \(particleCount)")
        
        // Обновляем конфигурацию с правильным количеством частиц
        var config = currentConfig
        config.targetParticleCount = particleCount
        
        // Инициализация ParticleSystem
        let system = ParticleSystemAssembly.makeCoordinator()
        
        // Инициализируем систему с изображением и конфигурацией
        system.initialize(with: image, particleCount: particleCount, config: config)
        
        // === ПОСЛЕДОВАТЕЛЬНОСТЬ ИНИЦИАЛИЗАЦИИ: 1. ПАЙПЛАЙНЫ ===
        logger.info("=== INITIALIZATION SEQUENCE: 1. PIPELINES ===")
        if let renderer = system.renderer as? MetalRenderer {
            do {
                try renderer.configureView(view)
                view.delegate?.mtkView(view, drawableSizeWillChange: view.drawableSize)
            } catch {
                logger.error("Failed to configure Metal renderer: \(error)")
                NotificationCenter.default.post(
                    name: .particleLoadFailed,
                    object: nil
                )
                return false
            }
        }
        
        // === ПОСЛЕДОВАТЕЛЬНОСТЬ ИНИЦИАЛИЗАЦИИ: 2. СИМУЛЯЦИЯ ===
        logger.info("=== INITIALIZATION SEQUENCE: 2. SIMULATION ===")
        // Сохранить ссылку
        particleSystem = system
        
        isConfigured = true
        logger.info("Particle system created – ready for interaction")
        
        // === ПОСЛЕДОВАТЕЛЬНОСТЬ ИНИЦИАЛИЗАЦИИ: 3. ГЕНЕРАЦИЯ ЧАСТИЦ ===
        logger.info("=== INITIALIZATION SEQUENCE: 3. PARTICLE GENERATION ===")
        // Фоновая генерация качественных частиц
        startQualityGeneration(for: system)
        
        logger.info("=== INITIALIZATION SEQUENCE COMPLETED SUCCESSFULLY ===")
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
        
        if system.isHighQuality {
            // Если HQ готовы — запускаем collecting (разбиение)
            system.simulationEngine.startCollecting()
            logger.info("Started particle scattering (breaking apart)")
            // Рендеринг управляется через MTKView в ViewController
        } else if isGeneratingHighQuality {
            // Если генерируются — показать сообщение
            logger.info("High-quality particles are generating, please wait...")
        } else {
            // Если HQ не готовы и не генерируются — начать симуляцию
            system.startSimulation()
            logger.info("Started chaotic simulation")
        }
    }
    
    /// Запускает «молниеносную бурю», если движок её поддерживает.
    @MainActor public func startLightningStorm() {
        particleSystem?.startLightningStorm()
    }
    
    /// Инициализирует fast preview частиц (для совместимости с ViewController).
    @MainActor public func initializeWithFastPreview() {
        particleSystem?.initializeFastPreview()
    }
    
    /// Запускает симуляцию (для совместимости с ViewController).
    @MainActor public func startSimulation() {
        particleSystem?.startSimulation()
    }
    
    // --------------------------------------------------------------------
    // MARK: - Private – High‑Quality Generation
    
    /// Запускает задачу, заменяющую быстрые частицы на качественные.
    @MainActor private func startQualityGeneration(for system: ParticleSystemCoordinator) {
        cancelQualityTask()
        isGeneratingHighQuality = true
        logger.info("Launching high‑quality particle generation")
        
        qualityTask = Task { [weak self] in
            guard let self else { return }
            
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            
            logger.info("Generating high‑quality particles…")
            logger.info("Starting high-quality replacement task for system")
            
            let success = await withCheckedContinuation { continuation in
                system.replaceWithHighQualityParticles { ok in
                    continuation.resume(returning: ok)
                }
            }
            
            isGeneratingHighQuality = false
            
            if success {
                logger.info("High‑quality particles ready")
                NotificationCenter.default.post(
                    name: .particleQualityUpgraded,
                    object: nil
                )
                // Рендеринг управляется через MTKView в ViewController
            } else {
                logger.warning("High‑quality particle generation failed")
                system.startSimulation()
                // Рендеринг управляется через MTKView в ViewController
            }
        }
    }
    
    /// Отменить фон. задачу, если она запущена.
    private func cancelQualityTask() {
        if qualityTask != nil {
            logger.info("Cancelling high-quality particle generation task")
        }
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
            Task { @MainActor in
                self?.handleLowMemory()
            }
        }
    }
    
    private func removeMemoryWarningObserver() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        memoryWarningObserver = nil
    }
    
    @MainActor
    private func handleLowMemory() {
        logger.warning("Low‑memory warning received – cleaning up")
        cleanupAllResources()
    }
    
    // --------------------------------------------------------------------
    // MARK: - Full Cleanup
    
    @MainActor
    public func cleanupAllResources() {
        logger.info("Performing full resource cleanup")
        
        cancelQualityTask()
        particleSystem?.cleanup()
        particleSystem = nil
        isConfigured = false
        removeMemoryWarningObserver()
        
        URLCache.shared.removeAllCachedResponses()
        clearTemporaryDirectory()
        
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
