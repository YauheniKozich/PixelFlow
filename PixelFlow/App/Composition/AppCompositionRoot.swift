import CoreGraphics
import Metal
import MetalKit
import UIKit

@MainActor
final class AppCompositionRoot {
    let logger: LoggerProtocol
    let errorHandler: ErrorHandlerProtocol
    let imageLoader: ImageLoaderProtocol
    let memoryManager: MemoryManagerProtocol

    let metalDevice: MTLDevice

    // These generator components retain only immutable configuration. Mutable
    // generation state is assembled with a shorter lifetime for each particle system.
    let imageAnalyzer: ImageAnalyzerProtocol
    let pixelSampler: PixelSamplerProtocol
    let particleAssembler: ParticleAssemblerProtocol
    let generationStrategy: GenerationStrategyProtocol

    // The cache is internally synchronized and backed by a shared on-disk index.
    // Keep one instance so separate view graphs coordinate access to the same cache.
    let cacheManager: CacheManagerProtocol

    init(logger: LoggerProtocol = Logger.shared) {
        self.logger = logger
        self.errorHandler = ErrorHandler(logger: logger)
        self.imageLoader = ImageLoader(logger: logger)
        self.memoryManager = MemoryManager(logger: logger)

        guard let metalDevice = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal device not available")
        }
        self.metalDevice = metalDevice

        let performanceParams = PerformanceParams(
            maxConcurrentOperations: ProcessInfo.processInfo.activeProcessorCount,
            useSIMD: true,
            enableCaching: true,
            cacheSizeLimit: 100
        )
        let generationConfig = ParticleGenerationConfig.standard
        self.imageAnalyzer = DefaultImageAnalyzer(config: performanceParams, logger: logger)
        self.pixelSampler = DefaultPixelSampler(config: generationConfig, logger: logger)
        self.particleAssembler = DefaultParticleAssembler(config: generationConfig, logger: logger)
        self.generationStrategy = AdaptiveStrategy(logger: logger)
        self.cacheManager = DefaultCacheManager(cacheSizeLimit: 100 * 1024 * 1024)
    }

    func makeParticleGenerator() -> ParticleGeneratorProtocol {
        // Context and pipeline are mutable during execution. Give each particle
        // system its own coordinator so its single-flight state cannot cross views.
        let context = GenerationContext(logger: logger)
        let pipeline = GenerationPipeline(
            analyzer: imageAnalyzer,
            sampler: pixelSampler,
            assembler: particleAssembler,
            strategy: generationStrategy,
            context: context,
            logger: logger
        )
        let operationManager = OperationManager(logger: logger)
        let coordinator = GenerationCoordinator(
            pipeline: pipeline,
            operationManager: operationManager,
            memoryManager: memoryManager,
            cacheManager: cacheManager,
            logger: logger,
            errorHandler: errorHandler
        )

        // Keep the concrete dependency: the adapter currently exposes no
        // coordinator substitution seam. Revisit the unused protocol registration in Phase 4.
        return ImageParticleGeneratorToParticleSystemAdapter(
            coordinator: coordinator,
            logger: logger
        )
    }

    func makeRenderView(frame: CGRect) -> RenderView {
        let view = MTKView(frame: frame, device: metalDevice)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        return view
    }

    func makeParticleSystem(for renderView: RenderView) -> ParticleSystemControlling? {
        guard let metalView = renderView as? MTKView else {
            return nil
        }

        let drawableSize = metalView.drawableSize
        let fallbackSize = metalView.bounds.size
        let viewSize = (drawableSize.width > 0 && drawableSize.height > 0) ? drawableSize : fallbackSize

        guard let storage = ParticleStorage(
            device: metalDevice,
            logger: logger,
            viewSize: viewSize
        ) else {
            fatalError("Failed to create ParticleStorage")
        }

        let renderer: MetalRenderer
        do {
            renderer = try MetalRenderer(device: metalDevice, logger: logger)
        } catch {
            fatalError("Failed to create MetalRenderer: \(error)")
        }

        let simulationStateMachine = SimulationStateMachine(logger: logger)
        let clock = DefaultSimulationClock()
        let simulationEngine = SimulationEngine(
            stateManager: simulationStateMachine,
            clock: clock,
            logger: logger,
            particleStorage: storage
        )
        let configManager = ConfigurationManager(logger: logger)
        let generator = makeParticleGenerator()
        let controller = ParticleSystemController(
            renderer: renderer,
            simulationEngine: simulationEngine,
            clock: clock,
            storage: storage,
            configManager: configManager,
            generator: generator,
            logger: logger
        )

        do {
            try controller.configureView(metalView)
        } catch {
            logger.error("Failed to configure Metal view: \(error.localizedDescription)")
            return nil
        }

        return controller
    }

    func makeParticleViewController() -> UIViewController {
        let viewModel = ParticleViewModel(
            logger: logger,
            imageLoader: imageLoader,
            errorHandler: errorHandler,
            renderViewFactory: { [self] frame in
                makeRenderView(frame: frame)
            },
            systemFactory: { [self] view in
                makeParticleSystem(for: view)
            }
        )

        return ParticleViewController(viewModel: viewModel)
    }
}
