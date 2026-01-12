//
//  ViewController.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 24.10.25.
//

import UIKit
import MetalKit

// MARK: - Logger
private let logger = Logger.shared

class ViewController: UIViewController {
    // MARK: - Properties
    private var mtkView: MTKView!
    private var displayLink: CADisplayLink?
    private let viewModel: ParticleViewModel

    // MARK: - Initialization
    init(viewModel: ParticleViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Lifecycle
    override func viewDidLoad() {
        super.viewDidLoad()

        view.backgroundColor = .black

        setupMetalView()
        setupGestures()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        mtkView.frame = view.bounds

        // Инициализировать систему частиц только один раз после layout
        guard !viewModel.isConfigured else { return }

        if viewModel.setupParticleSystem(with: mtkView, screenSize: view.bounds.size) {
            setupDisplayLink()
            activateGestures()
        }
    }

    override var prefersStatusBarHidden: Bool {
        return true
    }

    // MARK: - Private Methods
    private func setupMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.framebufferOnly = false
        mtkView.preferredFramesPerSecond = 60
        view.addSubview(mtkView)
    }

    private func activateGestures() {
        mtkView.isUserInteractionEnabled = true
    }


    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        mtkView.addGestureRecognizer(tapGesture)

        // Double tap for reset
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap(_:)))
        doubleTap.numberOfTapsRequired = 2
        mtkView.addGestureRecognizer(doubleTap)

        // Triple tap for lightning storm
        let tripleTap = UITapGestureRecognizer(target: self, action: #selector(handleTripleTap(_:)))
        tripleTap.numberOfTapsRequired = 3
        mtkView.addGestureRecognizer(tripleTap)

        // Single tap waits for double and triple taps to fail
        tapGesture.require(toFail: doubleTap)
        tapGesture.require(toFail: tripleTap)
        doubleTap.require(toFail: tripleTap)
    }


    private func setupDisplayLink() {
        displayLink = CADisplayLink(target: self, selector: #selector(renderLoop))
        displayLink?.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        displayLink?.add(to: .main, forMode: .common)
        logger.info("CADisplayLink запущен")
    }

    @objc private func renderLoop() {
        // Render only if simulation is active
        if viewModel.particleSystem?.hasActiveSimulation ?? false {
            mtkView.draw()
        } else {
            // Stop displayLink if simulation is finished
            displayLink?.isPaused = true
            logger.info("Симуляция завершена, displayLink остановлен")
        }
    }

    // MARK: - Gesture Handlers
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        // Only handle completed taps
        guard gesture.state == .ended else {
            logger.debug("handleTap игнорируется, состояние: \(gesture.state.rawValue)")
            return
        }

        logger.debug("handleTap выполнен")
        viewModel.handleSingleTap()
        displayLink?.isPaused = false
    }

    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        // Stop current simulation
        displayLink?.isPaused = true
        displayLink?.invalidate()
        displayLink = nil

        // Reset system
        viewModel.handleDoubleTap()

        // Reinitialize in next layout cycle
        view.setNeedsLayout()
    }

    @objc private func handleTripleTap(_ gesture: UITapGestureRecognizer) {
        viewModel.handleTripleTap()
        logger.info("⚡ Тройное нажатие: Гроза активирована!")
    }


    // MARK: - Deinitialization
    deinit {
        displayLink?.invalidate()
        displayLink = nil
        logger.debug("Деинициализация завершена")
    }
}
