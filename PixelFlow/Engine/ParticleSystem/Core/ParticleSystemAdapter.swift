//
//  ParticleSystemAdapter.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Адаптер для совместимости нового ParticleSystemCoordinator со старым API
//

import MetalKit
import CoreGraphics

/// Адаптер для совместимости с существующим API ParticleSystem
/// Позволяет постепенно перейти на новую архитектуру
final class ParticleSystemAdapter: NSObject {

    // MARK: - Properties

    private let coordinator: ParticleSystemCoordinator
    private let renderer: MetalRenderer
    private weak var mtkView: MTKView?
    private var displayLink: CADisplayLink?

    // MARK: - Public Properties (для совместимости)

    var enableIdleChaotic: Bool = false
    let device: MTLDevice
    let commandQueue: MTLCommandQueue
    let particleCount: Int
    var screenSize: CGSize = .zero
    var isConfigured = false
    var hasActiveSimulation: Bool { coordinator.hasActiveSimulation }
    var isHighQuality: Bool { coordinator.isHighQuality }
    var currentConfig: ParticleGenerationConfig { coordinator.configManager.currentConfig }

    // MARK: - Initialization

    init?(mtkView: MTKView, image: CGImage, particleCount: Int, config: ParticleGenerationConfig) {
        // Создаем новый координатор
        coordinator = ParticleSystemFactory.makeCoordinator()

        // Получаем renderer
        guard let renderer = coordinator.renderer as? MetalRenderer else {
            return nil
        }
        self.renderer = renderer

        self.device = renderer.device
        self.commandQueue = renderer.commandQueue
        self.particleCount = particleCount
        self.mtkView = mtkView

        super.init()

        // Инициализируем систему
        coordinator.initialize(with: image, particleCount: particleCount, config: config)

        // Настраиваем renderer
        renderer.setSimulationEngine(coordinator.simulationEngine)
        renderer.setParticleBuffer(coordinator.particleBuffer)

        // Настраиваем view
        configureView(mtkView)

        do {
            try renderer.setupPipelines()
            try renderer.setupBuffers(particleCount: particleCount)
        } catch {
            Logger.shared.error("Failed to setup Metal: \(error)")
            return nil
        }
    }

    // MARK: - Public API (совместимый со старым ParticleSystem)

    func toggleState() {
        coordinator.toggleSimulation()
    }

    func startSimulation() {
        coordinator.startSimulation()
    }

    func startLightningStorm() {
        coordinator.startLightningStorm()
    }

    func configure(screenSize: CGSize) {
        precondition(!isConfigured, "ParticleSystem уже сконфигурирован")
        self.screenSize = screenSize
        coordinator.configure(screenSize: screenSize)
        isConfigured = true
    }

    func initialize() {
        precondition(isConfigured, "Вызовите configure(screenSize:) перед initialize()")
        // Для совместимости - просто инициализируем
        coordinator.initializeFastPreview()
    }

    func initializeWithFastPreview() {
        precondition(isConfigured, "Вызовите configure(screenSize:) перед initialize()")
        coordinator.initializeFastPreview()
    }

    func replaceWithHighQualityParticles(completion: @escaping (Bool) -> Void) {
        precondition(isConfigured, "Система не сконфигурирована")
        coordinator.replaceWithHighQualityParticles(completion: completion)
    }

    func stop() {
        coordinator.stopSimulation()
        stopDisplayLink()
    }

    func cleanup() {
        stopDisplayLink()
        coordinator.cleanup()
    }

    func getSourceImage() -> CGImage? {
        return coordinator.sourceImage
    }

    // MARK: - Private Methods

    private func configureView(_ view: MTKView) {
        renderer.configureView(view)
    }

    private func setupDisplayLink() {
        guard displayLink == nil else { return }

        displayLink = CADisplayLink(target: self, selector: #selector(renderLoop))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
        displayLink?.isPaused = true
    }

    private func startDisplayLink() {
        if displayLink?.isPaused ?? true {
            displayLink?.isPaused = false
            mtkView?.isPaused = false
        }
    }

    private func stopDisplayLink() {
        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil
        mtkView?.isPaused = true
    }

    @objc private func renderLoop() {
        // Обновляем симуляцию
        coordinator.updateSimulation()

        // Запрашиваем перерисовку
        mtkView?.setNeedsDisplay()
    }

    // MARK: - Deinit

    deinit {
        stopDisplayLink()
        Logger.shared.debug("ParticleSystemAdapter deinitialized")
    }
}

// Note: Coordinator access is handled through dependency injection in init