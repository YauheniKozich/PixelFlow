//
//  ParticleSystemController.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Главный координатор системы частиц - реализация паттерна Facade
//

import Foundation
import MetalKit
import CoreGraphics
import QuartzCore

// MARK: - ParticleSystemController Protocol

@MainActor
protocol ParticleSystemControlling {
    var hasActiveSimulation: Bool { get }
    var isHighQuality: Bool { get }
    var particleCount: Int { get }
    var sourceImage: CGImage? { get }
    var particleBuffer: MTLBuffer? { get }
    
    func initialize(with image: CGImage,
                    particleCount: Int,
                    config: ParticleGenerationConfig)
    func startSimulation()
    func stopSimulation()
    func toggleSimulation()
    func startCollecting()
    func collectHighQualityImage()
    func startLightningStorm()
    func replaceWithHighQualityParticles(completion: @escaping (Bool) -> Void)
    func updateSimulation(deltaTime: Float)
    func checkCollectionCompletion()
    func cleanup()
    func handleWillResignActive()
    func handleDidBecomeActive()
    func updateRenderViewLayout(frame: CGRect, scale: CGFloat)
    func setRenderPaused(_ paused: Bool)
}

// MARK: - Main Implementation

@MainActor
final class ParticleSystemController: ParticleSystemControlling {
   
    // MARK: - Dependencies
    
    private let renderer: MetalRendererProtocol
    let simulationEngine: SimulationEngineProtocol
    private let clock: SimulationClockProtocol
    let storage: ParticleStorageProtocol
    private let configManager: ConfigurationManagerProtocol
    private let generator: ParticleGeneratorProtocol
    private let logger: LoggerProtocol
    
    // MARK: - State
    
    internal var sourceImage: CGImage?
    internal var particleCount: Int = 0
    private var isHighQualityMode: Bool = false
    private weak var mtkView: MTKView?
    
    // Task management
    private var generationTask: Task<Void, Never>?
    private var hqCollectTask: Task<Void, Never>?
    
    // State flags
    private var isCollectingHQ: Bool = false
    private var hasHighQualityTargets: Bool = false
    private var pendingCollectAfterHQ: Bool = false
    private var isImageAssembled: Bool = false
    
    // Completion handlers
    private var highQualityReadyCompletion: ((Bool) -> Void)?
    
    // MARK: - Initialization
    
    init(renderer: MetalRendererProtocol,
         simulationEngine: SimulationEngineProtocol,
         clock: SimulationClockProtocol,
         storage: ParticleStorageProtocol,
         configManager: ConfigurationManagerProtocol,
         generator: ParticleGeneratorProtocol,
         logger: LoggerProtocol) {
        
        self.renderer = renderer
        self.simulationEngine = simulationEngine
        self.clock = clock
        self.storage = storage
        self.configManager = configManager
        self.generator = generator
        self.logger = logger
        
        setupComponentConnections()
        
        logger.info("ParticleSystemController initialized")
        generator.clearCache()
    }
    
    // MARK: - Component Connections
    
    private func setupComponentConnections() {
        renderer.setSimulationEngine(simulationEngine)
        renderer.setParticleBuffer(storage.particleBuffer)
        setupCallbacks()
    }
    
    private func setupCallbacks() {
        simulationEngine.resetCounterCallback = { [weak self] in
            self?.renderer.resetCollectedCounter()
        }
    }

    func configureView(_ view: MTKView) throws {
        self.mtkView = view
        try renderer.configureView(view)
        view.delegate?.mtkView(view, drawableSizeWillChange: view.drawableSize)
    }
}

// MARK: - Initialization

extension ParticleSystemController {

    func initialize(with image: CGImage,
                    particleCount: Int,
                    config: ParticleGenerationConfig) {
        logger.info("Initializing with image: \(image.width)x\(image.height)")

        self.sourceImage = image
        self.particleCount = particleCount

        configManager.apply(config)
        storage.initialize(with: particleCount)

        do {
            try renderer.setupBuffers(particleCount: particleCount)
            renderer.updateParticleCount(particleCount)
        } catch {
            logger.error("Failed to setup renderer: \(error)")
        }

        logger.info("Controller initialized with \(particleCount) particles")

        // Подготовим sourcePixels для цветного предпросмотра
        if let cache = try? PixelCache.create(from: image) {
            let pixels = generatePreviewPixels(
                cache: cache,
                particleCount: particleCount,
                config: config
            )
            storage.setSourcePixels(pixels)
            logger.info("Seeded source pixels for preview: \(pixels.count)")
        } else {
            logger.warning("Failed to build PixelCache for preview colors")
        }

        // Быстрый предпросмотр: заполняем буфер, чтобы сразу что-то было видно
        storage.createFastPreviewParticles()
        renderer.setParticleBuffer(storage.particleBuffer)
        
        // Первый кадр, чтобы частицы были видны сразу
        if let view = mtkView,
           view.isPaused,
           view.drawableSize.width > 0,
           view.drawableSize.height > 0 {
            view.draw()
        }
        
        // Запускаем симуляцию, чтобы частицы начали двигаться сразу
        if !simulationEngine.isActive {
            startSimulation()
        }

        // Асинхронная генерация частиц
        cancelAllTasks()
        generationTask = Task { [weak self] in
            await self?.generateAndStartSimulation()
        }
    }
    
    private func generatePreviewPixels(
        cache: PixelCache,
        particleCount: Int,
        config: ParticleGenerationConfig
    ) -> [Pixel] {
        var pixels: [Pixel] = []
        pixels.reserveCapacity(particleCount)
        
        let w = cache.width
        let h = cache.height
        let viewSize = mtkView?.drawableSize ?? .zero
        let fallbackScale = mtkView?.contentScaleFactor ?? 1.0
        let fallbackSize = CGSize(
            width: (mtkView?.bounds.size.width ?? 0) * fallbackScale,
            height: (mtkView?.bounds.size.height ?? 0) * fallbackScale
        )
        let targetSize = (viewSize.width > 0 && viewSize.height > 0) ? viewSize : fallbackSize

        // Вычисляем трансформацию для предпросмотра
        let imagePixelSize = CGSize(width: w, height: h)
        let baseImageSize = imagePixelSize

        let baseScaleX = baseImageSize.width / imagePixelSize.width
        let baseScaleY = baseImageSize.height / imagePixelSize.height

        let isFullRes = particleCount >= w * h
        let transform = calculateTransform(
            imageSize: baseImageSize,
            screenSize: targetSize,
            mode: config.imageDisplayMode,
            snapToIntScale: isFullRes
        )

        // Вариант 1: если берем все пиксели, не используем сетку — проходим все координаты.
        if particleCount >= w * h {
            for y in 0..<h {
                for x in 0..<w {
                    if let c = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) {
                        let screenX = transform.offsetX + (CGFloat(x) + 0.5) * transform.scaleX * baseScaleX + transform.pixelCenterOffset
                        let screenY = transform.offsetY + (CGFloat(y) + 0.5) * transform.scaleY * baseScaleY + transform.pixelCenterOffset
                        pixels.append(
                            Pixel(
                                x: Int(screenX.rounded()),
                                y: Int(screenY.rounded()),
                                r: UInt8(clamping: Int(c.r * 255.0)),
                                g: UInt8(clamping: Int(c.g * 255.0)),
                                b: UInt8(clamping: Int(c.b * 255.0)),
                                a: UInt8(clamping: Int(c.a * 255.0))
                            )
                        )
                    }
                }
            }
            return pixels
        }
        
        // 2D-сетка для равномерного покрытия
        let aspectRatio = Double(w) / Double(h)
        let gridHeight = max(1, Int(sqrt(Double(particleCount) / aspectRatio)))
        let gridWidth = max(1, Int(ceil(Double(particleCount) / Double(gridHeight))))
        
        var samplesGenerated = 0

        // Равномерные координаты, включая края (чтобы не было "пустых" полос сверху/снизу)
        @inline(__always)
        func gridCoord(_ index: Int, _ gridSize: Int, _ maxCoord: Int) -> Int {
            guard gridSize > 1 else { return maxCoord / 2 }
            let t = Double(index) / Double(gridSize - 1)
            return Int((t * Double(maxCoord)).rounded())
        }
        
        outerLoop: for gy in 0..<gridHeight {
            for gx in 0..<gridWidth {
                guard samplesGenerated < particleCount else { break outerLoop }
                
                // Координаты по краям включительно (избегаем пропусков сверху/снизу)
                let x = gridCoord(gx, gridWidth, max(0, w - 1))
                let y = gridCoord(gy, gridHeight, max(0, h - 1))
                
                // Защита от выхода за границы
                let clampedX = min(x, w - 1)
                let clampedY = min(y, h - 1)
                
                if let c = PixelCacheHelper.getPixelData(atX: clampedX, y: clampedY, from: cache) {
                    let screenX = transform.offsetX + (CGFloat(clampedX) + 0.5) * transform.scaleX * baseScaleX + transform.pixelCenterOffset
                    let screenY = transform.offsetY + (CGFloat(clampedY) + 0.5) * transform.scaleY * baseScaleY + transform.pixelCenterOffset
                    
                    pixels.append(
                        Pixel(
                            x: Int(screenX.rounded()),
                            y: Int(screenY.rounded()),
                            r: UInt8(clamping: Int(c.r * 255.0)),
                            g: UInt8(clamping: Int(c.g * 255.0)),
                            b: UInt8(clamping: Int(c.b * 255.0)),
                            a: UInt8(clamping: Int(c.a * 255.0))
                        )
                    )
                    samplesGenerated += 1
                }
            }
        }
        
        return pixels
    }
    
    private struct Transform {
        let scaleX: CGFloat
        let scaleY: CGFloat
        let offsetX: CGFloat
        let offsetY: CGFloat
        let pixelCenterOffset: CGFloat
    }
    
    private func calculateTransform(
        imageSize: CGSize,
        screenSize: CGSize,
        mode: ImageDisplayMode,
        snapToIntScale: Bool
    ) -> Transform {
        let aspectImage = imageSize.width / imageSize.height
        let aspectScreen = screenSize.width / screenSize.height
        
        let scaleX: CGFloat
        let scaleY: CGFloat
        var offsetX: CGFloat
        var offsetY: CGFloat
        
        switch mode {
        case .fit:
            var modeScale = min(screenSize.width / imageSize.width,
                              screenSize.height / imageSize.height)
            if snapToIntScale, modeScale >= 1.0 {
                modeScale = floor(modeScale)
            }
            scaleX = modeScale
            scaleY = modeScale
            offsetX = (screenSize.width - imageSize.width * modeScale) / 2
            offsetY = (screenSize.height - imageSize.height * modeScale) / 2
            if snapToIntScale {
                offsetX = offsetX.rounded()
                offsetY = offsetY.rounded()
            }
            
        case .fill:
            var modeScale = (aspectImage > aspectScreen)
                ? screenSize.height / imageSize.height
                : screenSize.width / imageSize.width
            if snapToIntScale, modeScale >= 1.0 {
                modeScale = ceil(modeScale)
            }
            scaleX = modeScale
            scaleY = modeScale
            offsetX = (screenSize.width - imageSize.width * modeScale) / 2
            offsetY = (screenSize.height - imageSize.height * modeScale) / 2
            if snapToIntScale {
                offsetX = offsetX.rounded()
                offsetY = offsetY.rounded()
            }
            
        case .stretch:
            scaleX = screenSize.width / imageSize.width
            scaleY = screenSize.height / imageSize.height
            offsetX = 0
            offsetY = 0
            
        case .center:
            scaleX = 1.0
            scaleY = 1.0
            offsetX = (screenSize.width - imageSize.width) / 2
            offsetY = (screenSize.height - imageSize.height) / 2
        }
        
        let centerOffset: CGFloat = snapToIntScale ? 0.5 : 0.0
        return Transform(scaleX: scaleX, scaleY: scaleY, offsetX: offsetX, offsetY: offsetY, pixelCenterOffset: centerOffset)
    }

    private func logCollectViewSize(context: String) {
        guard let view = mtkView else { return }
        let drawable = view.drawableSize
        let bounds = view.bounds.size
        let scale = view.contentScaleFactor
        let scaleStr = String(format: "%.2f", scale)
        logger.info(
            "Collect \(context) viewSize: \(Int(drawable.width))x\(Int(drawable.height)) " +
            "(bounds: \(Int(bounds.width))x\(Int(bounds.height)), scale: \(scaleStr))"
        )
    }

    private func generateAndStartSimulation() async {
        if Task.isCancelled { return }
        guard let image = sourceImage, let view = mtkView else {
            logger.error("Cannot generate particles: missing image or view size")
            return
        }

        let viewSize = await resolveDrawableSize(for: view)
        storage.updateViewSize(viewSize)
        logger.info("HQ generation viewSize: \(Int(viewSize.width))x\(Int(viewSize.height)) (drawable: \(Int(view.drawableSize.width))x\(Int(view.drawableSize.height)))")

        logger.info("Starting particle generation for image \(image.width)x\(image.height)")
        
        do {
            var hqConfig = configManager.currentConfig
            hqConfig.qualityPreset = .ultra
            hqConfig.samplingStrategy = .hybrid
            hqConfig.targetParticleCount = particleCount

            // Генерация частиц
            let particles = try await generator.generateParticles(
                from: image,
                config: hqConfig,
                screenSize: viewSize
            )
            
            if Task.isCancelled { return }

            logger.info("Generated \(particles.count) particles from image")

            // Частицы уже в NDC [-1, 1]
            let preparedParticles = particles.map { particle -> Particle in
                var p = particle
                p.color[3] = 1.0 // полностью видимая альфа
                return p
            }

            if preparedParticles.isEmpty {
                logger.warning("Prepared particles array is empty")
            }

            // Обновляем storage и рендерер
            storage.updateParticles(preparedParticles)
            renderer.setParticleBuffer(storage.particleBuffer)
            renderer.updateParticleCount(preparedParticles.count)
            
            if Task.isCancelled { return }

            logger.info("Updated storage and renderer with \(preparedParticles.count) particles")

            // Готовим HQ цели для сборки
            storage.setHighQualityTargets(preparedParticles)
            simulationEngine.setHighQualityReady(true)
            hasHighQualityTargets = true
            isHighQualityMode = true
            
            // Вызываем completion
            highQualityReadyCompletion?(true)
            highQualityReadyCompletion = nil

            // Если был запрос на сборку до готовности HQ
            if pendingCollectAfterHQ {
                pendingCollectAfterHQ = false
                logCollectViewSize(context: "after HQ ready")
                simulationEngine.startCollectingToImage()
                // НЕ устанавливаем isImageAssembled здесь - дождемся завершения
            }

            // Запуск симуляции только если еще не активна
            if !simulationEngine.isActive {
                startSimulation()
                logger.info("Simulation started with \(preparedParticles.count) visible particles")
            } else {
                logger.info("Simulation already active - skipping start")
            }

        } catch {
            if !Task.isCancelled {
                logger.error("Particle generation failed: \(error)")
            }
            highQualityReadyCompletion?(false)
            highQualityReadyCompletion = nil
        }
    }
}

// MARK: - Simulation Control

extension ParticleSystemController {
    
    func startSimulation() {
        logger.info("Starting simulation")
        simulationEngine.start()
        mtkView?.isPaused = false
    }
    
    func stopSimulation() {
        logger.info("Stopping simulation")
        mtkView?.isPaused = true
        clock.reset()
        simulationEngine.stop()
    }
    
    func toggleSimulation() {
        if simulationEngine.isActive {
            stopSimulation()
        } else {
            startSimulation()
        }
    }

    func startCollecting() {
        simulationEngine.startCollecting()
    }
    
    func startLightningStorm() {
        logger.info("Starting lightning storm")
        simulationEngine.startLightningStorm()
    }
    
    func updateSimulation(deltaTime: Float) {
        simulationEngine.update(deltaTime: deltaTime)
    }

    // MARK: - Lifecycle Hooks

    func handleWillResignActive() {
        mtkView?.isPaused = true
        mtkView?.releaseDrawables()
    }

    func handleDidBecomeActive() {
        if simulationEngine.isActive {
            mtkView?.isPaused = false
        }
    }

    func updateRenderViewLayout(frame: CGRect, scale: CGFloat) {
        guard let view = mtkView else { return }
        if view.frame != frame {
            view.frame = frame
        }
        let clampedScale = scale > 0 ? scale : 1.0
        if view.contentScaleFactor != clampedScale {
            view.contentScaleFactor = clampedScale
        }
        let targetDrawableSize = CGSize(
            width: frame.size.width * clampedScale,
            height: frame.size.height * clampedScale
        )
        if view.drawableSize != targetDrawableSize {
            view.drawableSize = targetDrawableSize
        }
        storage.updateViewSize(view.drawableSize)
    }

    func setRenderPaused(_ paused: Bool) {
        mtkView?.isPaused = paused
    }

    func checkCollectionCompletion() {
        renderer.checkCollectionCompletion()
    }
}

// MARK: - Particle Generation

extension ParticleSystemController {
    
    func replaceWithHighQualityParticles(completion: @escaping (Bool) -> Void) {
        guard sourceImage != nil else {
            logger.error("No source image for high-quality generation")
            completion(false)
            return
        }

        // Если HQ частицы уже есть
        if hasHighQualityTargets {
            completion(true)
            return
        }

        // Если уже идет генерация
        if generationTask != nil {
            // Добавляем completion в очередь
            let previousCompletion = highQualityReadyCompletion
            highQualityReadyCompletion = { [weak self] success in
                previousCompletion?(success)
                completion(success)
            }
            return
        }

        // Запускаем новую генерацию
        highQualityReadyCompletion = completion
        generationTask = Task { [weak self] in
            await self?.generateAndStartSimulation()
        }
    }

    func collectHighQualityImage() {
        // Запрещаем сборку до готовности HQ-частиц
        guard hasHighQualityTargets else {
            logger.info("HQ not ready yet - collection blocked")
            return
        }

        // Предотвращаем множественные запуски
        guard !isCollectingHQ else {
            logger.info("HQ collect already in progress - skipping tap")
            return
        }

        if case .collecting = simulationEngine.state {
            logger.info("Collect already in progress - skipping tap")
            return
        }

        // Toggle между собранным и разлетевшимся состоянием
        if isImageAssembled {
            simulationEngine.startCollecting()
            isImageAssembled = false
            mtkView?.isPaused = false
            return
        }

        // HQ частицы готовы - собираем
        logCollectViewSize(context: "direct")
        simulationEngine.startCollectingToImage()
        isImageAssembled = true
        mtkView?.isPaused = false
    }

    private func generateHighQualityTargetsAndCollect() async {
        if Task.isCancelled { return }
        
        guard let image = sourceImage, let view = mtkView else {
            logger.error("Cannot collect image: missing image or view")
            return
        }

        let viewSize = await resolveDrawableSize(for: view)
        storage.updateViewSize(viewSize)
        logger.info("HQ collect viewSize: \(Int(viewSize.width))x\(Int(viewSize.height)) (drawable: \(Int(view.drawableSize.width))x\(Int(view.drawableSize.height)))")

        var hqConfig = configManager.currentConfig
        hqConfig.qualityPreset = .ultra
        hqConfig.samplingStrategy = .hybrid
        let desiredCount = image.width * image.height
        hqConfig.targetParticleCount = desiredCount
        configManager.apply(hqConfig)

        if desiredCount != particleCount {
            particleCount = desiredCount
            storage.initialize(with: desiredCount)

            do {
                try renderer.setupBuffers(particleCount: desiredCount)
                renderer.updateParticleCount(desiredCount)
            } catch {
                logger.error("Failed to setup renderer for HQ collect: \(error)")
                return
            }

            storage.createFastPreviewParticles()
            renderer.setParticleBuffer(storage.particleBuffer)
        }

        logger.info("Generating HQ particles for collection: \(desiredCount)")

        do {
            let particles = try await generator.generateParticles(
                from: image,
                config: hqConfig,
                screenSize: viewSize
            )
            
            if Task.isCancelled { return }

            let preparedParticles = particles.map { particle -> Particle in
                var p = particle
                p.color[3] = 1.0
                return p
            }

            storage.setHighQualityTargets(preparedParticles)
            simulationEngine.setHighQualityReady(true)
            hasHighQualityTargets = true
            isHighQualityMode = true
            
            // Запускаем сборку
            logCollectViewSize(context: "generated")
            simulationEngine.startCollectingToImage()
            isImageAssembled = true
            mtkView?.isPaused = false
            
        } catch {
            if Task.isCancelled {
                logger.warning("HQ collect generation cancelled")
            } else {
                logger.error("HQ collect generation failed: \(error)")
            }
        }
    }

    private func resolveDrawableSize(for view: MTKView) async -> CGSize {
        var size = view.drawableSize
        if size.width > 0 && size.height > 0 {
            return size
        }
        let fallback = CGSize(
            width: view.bounds.size.width * view.contentScaleFactor,
            height: view.bounds.size.height * view.contentScaleFactor
        )
        if fallback.width > 0 && fallback.height > 0 {
            size = fallback
        }
        // Подождем, пока MTKView сообщит корректный drawableSize
        for _ in 0..<60 { // ~1 сек при 60fps
            if Task.isCancelled { break }
            let current = view.drawableSize
            if current.width > 0 && current.height > 0 {
                return current
            }
            try? await Task.sleep(nanoseconds: 16_000_000)
        }
        return size
    }
}

// MARK: - Resource Management

extension ParticleSystemController {
    
    private func cancelAllTasks() {
        generationTask?.cancel()
        generationTask = nil
        hqCollectTask?.cancel()
        hqCollectTask = nil
    }
    
    func cleanup() {
        logger.info("Cleaning up controller")
        
        cancelAllTasks()
        stopSimulation()
        clock.reset()
        simulationEngine.reset()
        renderer.cleanup()
        storage.clear()
        generator.clearCache()
        
        sourceImage = nil
        particleCount = 0
        isHighQualityMode = false
        isImageAssembled = false
        hasHighQualityTargets = false
        pendingCollectAfterHQ = false
        isCollectingHQ = false
        highQualityReadyCompletion = nil
        
        logger.info("Controller cleaned up")
    }
}

// MARK: - Computed Properties

extension ParticleSystemController {
    
    var hasActiveSimulation: Bool {
        simulationEngine.isActive
    }
    
    var isHighQuality: Bool {
        isHighQualityMode
    }
    
    var particleBuffer: MTLBuffer? {
        storage.particleBuffer
    }
}
