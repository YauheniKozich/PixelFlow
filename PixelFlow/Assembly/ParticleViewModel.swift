//
//  ParticleViewModel.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.

import Foundation
import CoreGraphics
#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

// MARK: - Particle View Model

/// Управляет загрузкой изображения, созданием `ParticleSystem`,
/// переключением от быстрого превью к качественным частицам,
/// обработкой low‑memory и небольшим публичным API, пригодным для unit‑тестов.
@MainActor
final class ParticleViewModel {
    
    // MARK: - Constants
    
    private enum Constants {
        static let qualityGenerationDelay: UInt64 = 100_000_000 // 0.1 секунды в наносекундах
        static let smallImagePixelThreshold = 300_000
        static let tempFilePrefix = "ParticleCache_"
    }
    
    // MARK: - Public State
    
    public private(set) var isConfigured = false
    public private(set) var isGeneratingHighQuality = false
    public private(set) var particleSystem: ParticleSystemControlling?
    
    // MARK: - Callbacks
    
    public var onQualityUpgraded: (() -> Void)?
    
    // MARK: - Dependencies
    
    private let logger: LoggerProtocol
    private let imageLoader: ImageLoaderProtocol
    private let errorHandler: ErrorHandlerProtocol
    private let renderViewFactory: @MainActor (CGRect) -> RenderView
    private let systemFactory: @MainActor (RenderView) -> ParticleSystemControlling?
    
    // MARK: - Private State
    
    private var currentConfig = ParticleGenerationConfig.standard
    private var renderView: RenderView?
    private var qualityTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    public init(
        logger: LoggerProtocol,
        imageLoader: ImageLoaderProtocol,
        errorHandler: ErrorHandlerProtocol,
        renderViewFactory: @escaping @MainActor (CGRect) -> RenderView,
        systemFactory: @escaping @MainActor (RenderView) -> ParticleSystemControlling?
    ) {
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
    
    // MARK: - Configuration
    
    private func apply(_ newConfig: ParticleGenerationConfig) {
        currentConfig = newConfig
        logger.info("New configuration applied: \(newConfig)")
        
        if isConfigured {
            resetParticleSystem()
        }
    }
    
    func setImageDisplayMode(_ mode: ImageDisplayMode) {
        guard currentConfig.imageDisplayMode != mode else { return }
        
        var updated = currentConfig
        updated.imageDisplayMode = mode
        apply(updated)
    }
    
    private func applyDraftPreset() {
        apply(ParticleGenerationConfig.draft)
    }
    
    private func applyStandardPreset() {
        apply(ParticleGenerationConfig.standard)
    }
    
    private func applyHighPreset() {
        apply(ParticleGenerationConfig.high)
    }
    
    private func applyUltraPreset() {
        apply(ParticleGenerationConfig.ultra)
    }
    
    // MARK: - System Lifecycle
    
    /// Создаёт и запускает `ParticleSystem` в переданном render view.
    /// Возвращает `true`, если всё прошло успешно.
    func createSystem(in view: RenderView) async -> Bool {
        guard !isConfigured else {
            logger.info("Particle system is already configured")
            return true
        }
        
        logger.info("=== STARTING PARTICLE SYSTEM INITIALIZATION ===")
        
        guard let imageInfo = loadSourceImage() else {
            return false
        }
        
        let config = createSystemConfiguration(from: imageInfo, view: view)
        
        guard let system = initializeParticleSystem(view: view, image: imageInfo.cgImage, config: config) else {
            return false
        }
        
        finalizeSystemSetup(system: system)
        
        logger.info("=== INITIALIZATION SEQUENCE COMPLETED SUCCESSFULLY ===")
        return true
    }
    
    private func loadSourceImage() -> LoadedImage? {
        logger.info("Loading source image…")
        
        guard let loaded = imageLoader.loadImageInfoWithFallback() else {
            logger.error("Failed to load source image")
            errorHandler.handle(
                PixelFlowError.missingImage,
                context: "ParticleViewModel.createSystem",
                recovery: .showUserMessage("Не удалось загрузить изображение")
            )
            return nil
        }
        
        logger.info("Loaded image: \(loaded.cgImage.width)x\(loaded.cgImage.height) pixels")
        return loaded
    }
    
    private func createSystemConfiguration(
        from imageInfo: LoadedImage,
        view: RenderView
    ) -> ParticleGenerationConfig {
        
        let image = imageInfo.cgImage
        let totalPixels = image.width * image.height
        
        let effectivePreset = determineEffectivePreset(totalPixels: totalPixels)
        let screenScale = calculateScreenScale(for: view)
        
        var config = currentConfig
        config.qualityPreset = effectivePreset
        config.targetParticleCount = totalPixels
        config.imagePointWidth = Float(imageInfo.pointSize.width)
        config.imagePointHeight = Float(imageInfo.pointSize.height)
        config.screenScale = Float(screenScale)
        
        logger.info("Using image size: \(image.width)x\(image.height) for particle generation")
        logger.info("Full-res particle count (all pixels): \(totalPixels)")
        
        return config
    }
    
    private func determineEffectivePreset(totalPixels: Int) -> QualityPreset {
        if currentConfig.qualityPreset != .ultra && totalPixels <= Constants.smallImagePixelThreshold {
            logger.info("Promoting preset to ultra for full-res rendering (\(totalPixels) pixels)")
            return .ultra
        }
        return currentConfig.qualityPreset
    }
    
    private func calculateScreenScale(for view: RenderView) -> CGFloat {
        #if os(iOS)
        return calculateiOSScreenScale(for: view)
        #elseif os(macOS)
        return calculatemacOSScreenScale(for: view)
        #else
        return 1.0
        #endif
    }
    
    #if os(iOS)
    private func calculateiOSScreenScale(for view: RenderView) -> CGFloat {
        guard let uiView = view as? UIView else {
            return 1.0
        }
        
        if let screen = uiView.window?.windowScene?.screen {
            return screen.scale
        }
        
        return uiView.traitCollection.displayScale
    }
    #endif
    
    #if os(macOS)
    private func calculatemacOSScreenScale(for view: RenderView) -> CGFloat {
        guard let nsView = view as? NSView else {
            return NSScreen.main?.backingScaleFactor ?? 1.0
        }
        
        if let screen = nsView.window?.screen {
            return screen.backingScaleFactor
        }
        
        return NSScreen.main?.backingScaleFactor ?? 1.0
    }
    #endif
    
    private func initializeParticleSystem(
        view: RenderView,
        image: CGImage,
        config: ParticleGenerationConfig
    ) -> ParticleSystemControlling? {
        
        logger.info("=== INITIALIZATION SEQUENCE: 1. PIPELINES ===")
        logger.info("Creating particle system controller…")
        
        if particleSystem == nil {
            particleSystem = systemFactory(view)
        }
        
        guard let system = particleSystem else {
            logger.error("Failed to create particle system controller")
            errorHandler.handle(
                PixelFlowError.invalidContext,
                context: "ParticleViewModel.createSystem",
                recovery: .showUserMessage("Ошибка инициализации рендера")
            )
            return nil
        }
        
        logger.info("=== INITIALIZATION SEQUENCE: 2. SIMULATION ===")
        logger.info("Initializing system with image and config…")
        
        let particleCount = image.width * image.height
        system.initialize(with: image, particleCount: particleCount, config: config)
        
        return system
    }
    
    private func finalizeSystemSetup(system: ParticleSystemControlling) {
        particleSystem = system
        isConfigured = true
        
        logger.info("Particle system created – ready for interaction")
        logger.info("=== INITIALIZATION SEQUENCE: 3. PARTICLE GENERATION ===")
        
        startQualityGeneration(for: system)
    }
    
    func resetParticleSystem() {
        logger.info("Resetting particle system")
        cancelQualityTask()
        particleSystem?.cleanup()
        particleSystem = nil
        isConfigured = false
    }
    
    // MARK: - System Control
    
    func toggleSimulation() {
        guard let system = particleSystem else { return }
        
        guard !isGeneratingHighQuality && system.isHighQuality else {
            logger.info("High-quality particles are not ready yet, skipping collect")
            return
        }
        
        system.collectHighQualityImage()
        logger.info("Started high-quality image collection")
    }
    
    func startLightningStorm() {
        particleSystem?.startLightningStorm()
    }
    
    func initializeWithFastPreview() {
        // Оставлено для совместимости с ViewController
    }
    
    func startSimulation() {
        particleSystem?.startSimulation()
    }
    
    // MARK: - Rendering Control
    
    func pauseRendering() {
        updateRenderPaused(true)
    }
    
    func resumeRendering() {
        updateRenderPaused(false)
    }
    
    private func updateRenderPaused(_ paused: Bool) {
        particleSystem?.setRenderPaused(paused)
    }
    
    // MARK: - Lifecycle Events
    
    func handleWillResignActive() {
        particleSystem?.handleWillResignActive()
    }
    
    func handleDidBecomeActive() {
        particleSystem?.handleDidBecomeActive()
    }
    
    // MARK: - Render View Management
    
    func makeRenderView(frame: CGRect) -> RenderView {
        if renderView == nil {
            renderView = renderViewFactory(frame)
        }
        return renderView!
    }
    
    func updateRenderViewLayout(frame: CGRect, scale: CGFloat) {
        guard let system = particleSystem else { return }
        system.updateRenderViewLayout(frame: frame, scale: scale)
    }
    
    // MARK: - High Quality Generation
    
    private func startQualityGeneration(for system: ParticleSystemControlling) {
        cancelQualityTask()
        isGeneratingHighQuality = true
        logger.info("Launching high‑quality particle generation")
        
        qualityTask = Task { [weak self] in
            guard let self else { return }
            
            await self.executeQualityGenerationWithDelay(for: system)
        }
    }
    
    private func executeQualityGenerationWithDelay(for system: ParticleSystemControlling) async {
        try? await Task.sleep(nanoseconds: Constants.qualityGenerationDelay)
        
        guard !Task.isCancelled else { return }
        
        await performQualityGeneration(for: system)
    }
    
    private func performQualityGeneration(for system: ParticleSystemControlling) async {
        logger.info("Generating high‑quality particles…")
        logger.info("Starting high-quality replacement task for system")
        
        let success = await requestHighQualityReplacement(for: system)
        
        handleQualityGenerationCompletion(success: success, system: system)
    }
    
    private func requestHighQualityReplacement(for system: ParticleSystemControlling) async -> Bool {
        return await withCheckedContinuation { continuation in
            system.replaceWithHighQualityParticles { success in
                continuation.resume(returning: success)
            }
        }
    }
    
    private func handleQualityGenerationCompletion(success: Bool, system: ParticleSystemControlling) {
        isGeneratingHighQuality = false
        
        if success {
            logger.info("High‑quality particles ready")
            onQualityUpgraded?()
        } else {
            logger.warning("High‑quality particle generation failed")
            system.startSimulation()
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
    
    // MARK: - Memory Management
    
    func handleLowMemory() {
        logger.warning("Low‑memory warning received – cleaning up")
        cleanupAllResources()
    }
    
    func cleanupAllResources() {
        logger.info("Performing full resource cleanup")
        
        cleanupParticleSystem()
        cleanupCaches()
        
        logger.info("All resources released")
    }
    
    private func cleanupParticleSystem() {
        cancelQualityTask()
        particleSystem?.cleanup()
        particleSystem = nil
        isConfigured = false
    }
    
    private func cleanupCaches() {
        URLCache.shared.removeAllCachedResponses()
        clearTemporaryDirectory()
    }
    
    private func clearTemporaryDirectory() {
        let tmp = FileManager.default.temporaryDirectory
        
        do {
            let entries = try FileManager.default.contentsOfDirectory(
                at: tmp,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            )
            
            removeParticleCacheFiles(from: entries)
        } catch {
        }
    }
    
    private func removeParticleCacheFiles(from urls: [URL]) {
        for url in urls where url.lastPathComponent.hasPrefix(Constants.tempFilePrefix) {
            try? FileManager.default.removeItem(at: url)
        }
    }
    
    // MARK: - Particle Count Calculation
    
    /// Вычисляет количество частиц, учитывая плотность, зависящую от `QualityPreset`.
    private func optimalParticleCount(
        for image: CGImage,
        preset: QualityPreset
    ) -> Int {
        let totalPixels = image.width * image.height
        logger.info("optimalParticleCount – using full-res pixels:\(totalPixels) for preset:\(preset)")
        return totalPixels
    }
}
