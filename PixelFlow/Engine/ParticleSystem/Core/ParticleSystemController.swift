//
//  ParticleSystemController.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Главный координатор системы частиц - реализация паттерна Facade
//

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
    private var generationTask: Task<Void, Never>?
    private var hqCollectTask: Task<Void, Never>?
    private var isCollectingHQ: Bool = false
    private var hasHighQualityTargets: Bool = false
    private var pendingCollectAfterHQ: Bool = false
    private var highQualityReadyCompletion: ((Bool) -> Void)?
    private var isImageAssembled: Bool = false
    
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

            // Вычисляем трансформацию для предпросмотра с учетом режима отображения.
            let imagePixelSize = CGSize(width: w, height: h)
            let screenSize = targetSize

            // Use raw pixel size for preview mapping to keep pixel-perfect alignment.
            let baseImageSize = imagePixelSize

            // Масштаб от пикселей изображения к базовому размеру (учет UIImage.scale)
            let baseScaleX = baseImageSize.width / imagePixelSize.width
            let baseScaleY = baseImageSize.height / imagePixelSize.height

            let scaleX: CGFloat
            let scaleY: CGFloat
            let offsetX: CGFloat
            let offsetY: CGFloat
            let aspectImage = baseImageSize.width / baseImageSize.height
            let aspectScreen = screenSize.width / screenSize.height

            switch config.imageDisplayMode {
            case .fit:
                // Масштабируем изображение, чтобы оно полностью помещалось на экране.
                let modeScale: CGFloat = min(screenSize.width / baseImageSize.width,
                                             screenSize.height / baseImageSize.height)
                scaleX = baseScaleX * modeScale
                scaleY = baseScaleY * modeScale
                offsetX = (screenSize.width - baseImageSize.width * modeScale) / 2
                offsetY = (screenSize.height - baseImageSize.height * modeScale) / 2
            case .fill:
                let modeScale: CGFloat = (aspectImage > aspectScreen)
                    ? screenSize.height / baseImageSize.height
                    : screenSize.width / baseImageSize.width
                scaleX = baseScaleX * modeScale
                scaleY = baseScaleY * modeScale
                offsetX = (screenSize.width - baseImageSize.width * modeScale) / 2
                offsetY = (screenSize.height - baseImageSize.height * modeScale) / 2
            case .stretch:
                let modeScaleX = screenSize.width / baseImageSize.width
                let modeScaleY = screenSize.height / baseImageSize.height
                scaleX = baseScaleX * modeScaleX
                scaleY = baseScaleY * modeScaleY
                offsetX = 0
                offsetY = 0
            case .center:
                scaleX = baseScaleX
                scaleY = baseScaleY
                offsetX = (screenSize.width - baseImageSize.width) / 2
                offsetY = (screenSize.height - baseImageSize.height) / 2
            }
            for _ in 0..<particleCount {
                let x = Int.random(in: 0..<w)
                let y = Int.random(in: 0..<h)
                if let c = PixelCacheHelper.getPixelData(atX: x, y: y, from: cache) {
                    let screenX = offsetX + (CGFloat(x) + 0.5) * scaleX
                    let screenY = offsetY + (CGFloat(y) + 0.5) * scaleY
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
        generationTask?.cancel()
        generationTask = Task { [weak self] in
            await self?.generateAndStartSimulation()
        }
    }

    private func generateAndStartSimulation() async {
        if Task.isCancelled { return }
        guard let image = sourceImage, let view = mtkView else {
            logger.error("Cannot generate particles: missing image or view size")
            return
        }

        let viewSize = view.drawableSize.width > 0 && view.drawableSize.height > 0
        ? view.drawableSize
        : CGSize(
            width: view.bounds.size.width * view.contentScaleFactor,
            height: view.bounds.size.height * view.contentScaleFactor
        )

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

            // Частицы уже в NDC [-1, 1]. Не масштабируем в пиксели, иначе уйдут за экран.
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
            highQualityReadyCompletion?(true)
            highQualityReadyCompletion = nil

            if pendingCollectAfterHQ {
                pendingCollectAfterHQ = false
                isImageAssembled = true
                simulationEngine.startCollectingToImage()
            }

            // Запуск симуляции
            startSimulation()
            logger.info("Simulation started with \(preparedParticles.count) visible particles")

        } catch {
            highQualityReadyCompletion?(false)
            highQualityReadyCompletion = nil
            logger.error("Particle generation failed: \(error)")
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

    // MARK: - Lifecycle Hooks (driven by SceneDelegate)

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

        if hasHighQualityTargets {
            completion(true)
            return
        }

        highQualityReadyCompletion = completion

        if generationTask == nil {
            generationTask = Task { [weak self] in
                await self?.generateAndStartSimulation()
            }
        }
    }

    func collectHighQualityImage() {
        guard !isCollectingHQ else {
            logger.info("HQ collect already in progress - skipping tap")
            return
        }

        if case .collecting = simulationEngine.state {
            logger.info("Collect already in progress - skipping tap")
            return
        }

        if isImageAssembled {
            // Toggle to scatter (break apart)
            simulationEngine.startCollecting()
            isImageAssembled = false
            mtkView?.isPaused = false
            return
        }

        if hasHighQualityTargets {
            simulationEngine.startCollectingToImage()
            isImageAssembled = true
            mtkView?.isPaused = false
            return
        }

        pendingCollectAfterHQ = true

        if generationTask == nil {
            hqCollectTask?.cancel()
            hqCollectTask = Task { [weak self] in
                await self?.generateHighQualityTargetsAndCollect()
            }
        }
    }

    private func generateHighQualityTargetsAndCollect() async {
        if isCollectingHQ { return }
        isCollectingHQ = true
        defer { isCollectingHQ = false }
        if Task.isCancelled { return }
        guard let image = sourceImage, let view = mtkView else {
            logger.error("Cannot collect image: missing image or view")
            return
        }

        let viewSize = view.drawableSize.width > 0 && view.drawableSize.height > 0
        ? view.drawableSize
        : CGSize(
            width: view.bounds.size.width * view.contentScaleFactor,
            height: view.bounds.size.height * view.contentScaleFactor
        )

        var hqConfig = configManager.currentConfig
        hqConfig.qualityPreset = .ultra
        hqConfig.samplingStrategy = .hybrid
        let desiredCount = configManager.optimalParticleCount(for: image, preset: .ultra)
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
            isImageAssembled = true
            simulationEngine.startCollectingToImage()
            mtkView?.isPaused = false
            isHighQualityMode = true
        } catch {
            if Task.isCancelled {
                logger.warning("HQ collect generation cancelled")
            } else {
                logger.error("HQ collect generation failed: \(error)")
            }
        }
    }
}

// MARK: - Resource Management

extension ParticleSystemController {
    
    func cleanup() {
        logger.info("Cleaning up controller")
        
        generationTask?.cancel()
        generationTask = nil
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
