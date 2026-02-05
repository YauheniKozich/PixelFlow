//
//  ParticleViewModel.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.

import Foundation
import CoreGraphics

// MARK: - ParticleViewModel

/// Управляет загрузкой изображения, созданием `ParticleSystem`,
/// переключением от быстрого превью к качественным частицам,
/// обработкой low‑memory и небольшим публичным API, пригодным для unit‑тестов.
@MainActor
final class ParticleViewModel {
    
    // MARK: - Public read‑only state
    
    public private(set) var isConfigured = false
    public private(set) var isGeneratingHighQuality = false
    public private(set) var particleSystem: ParticleSystemControlling?
    
    // MARK: - UI Callbacks
    
    public var onQualityUpgraded: (() -> Void)?
    
    // MARK: - Private storage
    
    private let logger: LoggerProtocol
    private let imageLoader: ImageLoaderProtocol
    private let errorHandler: ErrorHandlerProtocol
    private let renderViewFactory: @MainActor (CGRect) -> RenderView
    private let systemFactory: @MainActor (RenderView) -> ParticleSystemControlling?
    private var currentConfig = ParticleGenerationConfig.standard
    private var renderView: RenderView?
    private var qualityTask: Task<Void, Never>?
    
    // --------------------------------------------------------------------
    // MARK: - Life‑cycle
    
    public init(logger: LoggerProtocol,
                imageLoader: ImageLoaderProtocol,
                errorHandler: ErrorHandlerProtocol,
                renderViewFactory: @escaping @MainActor (CGRect) -> RenderView,
                systemFactory: @escaping @MainActor (RenderView) -> ParticleSystemControlling?) {
        self.logger = logger
        self.imageLoader = imageLoader
        self.errorHandler = errorHandler
        self.renderViewFactory = renderViewFactory
        self.systemFactory = systemFactory
        logger.info("ParticleViewModel init")
    }
    
    deinit {
        let cancellableTask = { [weak self] in
            await self?.cancelQualityTask()
        }
        
        Task {
            await cancellableTask()
        }
        particleSystem = nil
        logger.info("ParticleViewModel deinit")
    }
    
    // --------------------------------------------------------------------
    // MARK: - Public API – Configuration
    
    private func apply(_ newConfig: ParticleGenerationConfig) {
        currentConfig = newConfig
        logger.info("New configuration applied: \(newConfig)")
        
        // Если система уже существует – сбрасываем её,
        // чтобы при следующем `createSystem` использовалась новая конфигурация.
        if isConfigured {
            resetParticleSystem()
        }
    }
    
    private func applyDraftPreset()   { apply(ParticleGenerationConfig.draft)   }
    private func applyStandardPreset() { apply(ParticleGenerationConfig.standard) }
    private func applyHighPreset()    { apply(ParticleGenerationConfig.high)    }
    private func applyUltraPreset()   { apply(ParticleGenerationConfig.ultra)   }
    
    // --------------------------------------------------------------------
    // MARK: - Public API – System Lifecycle
    
    /// Создаёт и запускает `ParticleSystem` в переданном render view.
    /// Возвращает `true`, если всё прошло успешно.
    func createSystem(in view: RenderView) async -> Bool {
        guard !isConfigured else {
            logger.info("Particle system is already configured")
            return true
        }
        
        logger.info("=== STARTING PARTICLE SYSTEM INITIALIZATION ===")
        
        // Загрузка изображения
        logger.info("Loading source image…")
        guard let image = imageLoader.loadImageWithFallback() else {
            logger.error("Failed to load source image")
            errorHandler.handle(PixelFlowError.missingImage,
                                context: "ParticleViewModel.createSystem",
                                recovery: .showUserMessage("Не удалось загрузить изображение"))
            return false
        }
        logger.info("Loaded image: \(image.width)x\(image.height) pixels")
        
        logger.info("Source image loaded: \(image.width)x\(image.height)")
        
        // Вычисление количества частиц
        let particleCount = optimalParticleCount(for: image,
                                                 preset: currentConfig.qualityPreset)
        logger.info("Using image size: \(image.width)x\(image.height) for particle generation")
        logger.info("Calculated particle count: \(particleCount)")
        
        // Обновляем конфигурацию с правильным количеством частиц
        var config = currentConfig
        config.targetParticleCount = particleCount
        
        // Инициализация ParticleSystem
        logger.info("Creating particle system controller…")
        if particleSystem == nil {
            particleSystem = systemFactory(view)
        }
        guard let system = particleSystem else {
            logger.error("Failed to create particle system controller")
            errorHandler.handle(PixelFlowError.invalidContext,
                                context: "ParticleViewModel.createSystem",
                                recovery: .showUserMessage("Ошибка инициализации рендера"))
            return false
        }
        // Инициализируем систему с изображением и конфигурацией
        logger.info("Initializing system with image and config…")
        system.initialize(with: image, particleCount: particleCount, config: config)
        
        // === ПОСЛЕДОВАТЕЛЬНОСТЬ ИНИЦИАЛИЗАЦИИ: 1. ПАЙПЛАЙНЫ ===
        logger.info("=== INITIALIZATION SEQUENCE: 1. PIPELINES ===")
        
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
    
    func resetParticleSystem() {
        logger.info("Resetting particle system")
        cancelQualityTask()
        particleSystem?.cleanup()
        particleSystem = nil
        isConfigured = false
    }
    
    func toggleSimulation() {
        guard let system = particleSystem else { return }
        
        if isGeneratingHighQuality {
            logger.info("High-quality particles are generating, please wait...")
            return
        }
        
        system.collectHighQualityImage()
        logger.info("Started high-quality image collection")
    }
    
    /// Запускает «молниеносную бурю», если движок её поддерживает.
    func startLightningStorm() {
        particleSystem?.startLightningStorm()
    }
    
    // MARK: - Lifecycle Signals (from UI / SceneDelegate)
    
    func handleWillResignActive() {
        particleSystem?.handleWillResignActive()
    }
    
    func handleDidBecomeActive() {
        particleSystem?.handleDidBecomeActive()
    }
    
    // MARK: - Render View Factory
    
    func makeRenderView(frame: CGRect) -> RenderView {
        if renderView == nil {
            renderView = renderViewFactory(frame)
        }
        return renderView!
    }
    
    // MARK: - Render View Layout (from UI)
    
    func updateRenderViewLayout(frame: CGRect, scale: CGFloat) {
        guard let system = particleSystem else { return }
        system.updateRenderViewLayout(frame: frame, scale: scale)
    }
    
    /// Инициализирует fast preview частиц (для совместимости с ViewController).
    func initializeWithFastPreview() {
        //  particleSystem?.initializeFastPreview()
    }
    
    /// Запускает симуляцию (для совместимости с ViewController).
    func startSimulation() {
        particleSystem?.startSimulation()
    }
    
    func pauseRendering() {
        updateRenderPaused(true)
    }
    
    func resumeRendering() {
        updateRenderPaused(false)
    }
    
    private func updateRenderPaused(_ paused: Bool) {
        particleSystem?.setRenderPaused(paused)
    }
    
    // MARK: - Private – High‑Quality Generation
    
    /// Запускает задачу, заменяющую быстрые частицы на качественные.
    func startQualityGeneration(for system: ParticleSystemControlling) {
        cancelQualityTask()
        isGeneratingHighQuality = true
        logger.info("Launching high‑quality particle generation")
        
        qualityTask = Task { [weak self] in
            guard let self else { return }
            
            try? await Task.sleep(nanoseconds: 100_000_000)
            guard !Task.isCancelled else { return }
            
            await self.performQualityGeneration(for: system)
        }
    }
    
    private func performQualityGeneration(for system: ParticleSystemControlling) async {
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
            onQualityUpgraded?()
            // Рендеринг управляется через render view в ViewController
        } else {
            logger.warning("High‑quality particle generation failed")
            system.startSimulation()
            // Рендеринг управляется через render view в ViewController
        }
    }
    
    private func cancelQualityTask() {
        if qualityTask != nil {
            logger.info("Cancelling high-quality particle generation task")
        }
        qualityTask?.cancel()
        qualityTask = nil
        isGeneratingHighQuality = false
    }
    
    // MARK: - Low‑Memory Handling
    
    func handleLowMemory() {
        logger.warning("Low‑memory warning received – cleaning up")
        cleanupAllResources()
    }
    
    // MARK: - Full Cleanup
    
    func cleanupAllResources() {
        logger.info("Performing full resource cleanup")
        
        cancelQualityTask()
        particleSystem?.cleanup()
        particleSystem = nil
        isConfigured = false
        
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
}
