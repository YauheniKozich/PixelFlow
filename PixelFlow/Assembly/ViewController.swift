//
//  ViewController.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 24.10.25.
//

import UIKit
import MetalKit

class ViewController: UIViewController {
    
    // MARK: - Свойства
    
    private var mtkView: MTKView!
    private let viewModel: ParticleViewModel
    private var qualityUpgradeLabel: UILabel?
    private var isFirstLayout = true
    
    // MARK: - Инициализация
    
    init(viewModel: ParticleViewModel) {
        self.viewModel = viewModel
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    // MARK: - Жизненный цикл
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        setupMetalView()
        setupGestures()
        setupQualityUpgradeNotification()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        mtkView.frame = view.bounds
        // Установить drawableSize при layout
        mtkView.drawableSize = mtkView.bounds.size
        // Вызываем делегат чтобы обновить screenSize в MetalRenderer
        mtkView.delegate?.mtkView(mtkView, drawableSizeWillChange: mtkView.bounds.size)
        
        // Инициализируем систему частиц только один раз после layout
        guard isFirstLayout else { return }
        
        if isFirstLayout {
            isFirstLayout = false
            
            Task { @MainActor in
                if  viewModel.isConfigured { return }
                
                if await viewModel.createSystem(in: mtkView) {
                    startRenderingIfNeeded()
                    activateGestures()
                }
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRenderingIfNeeded()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        mtkView.isPaused = true
    }
    
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    // MARK: - Настройка MetalView
    
    private func setupMetalView() {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal не поддерживается на этом устройстве")
        }
        
        mtkView = MTKView(frame: view.bounds, device: device)
        mtkView.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        mtkView.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        mtkView.colorPixelFormat = .bgra8Unorm_srgb
        mtkView.framebufferOnly = true
        mtkView.preferredFramesPerSecond = 60
        mtkView.isPaused = true
        mtkView.enableSetNeedsDisplay = false
        
        view.addSubview(mtkView)
    }
    
    private func activateGestures() {
        mtkView.isUserInteractionEnabled = true
    }
    
    // MARK: - Настройка жестов
    
    private func setupGestures() {
        let tapGesture = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        view.addGestureRecognizer(tapGesture)
        
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        view.addGestureRecognizer(doubleTap)
        
        let tripleTap = UITapGestureRecognizer(target: self, action: #selector(handleTripleTap))
        tripleTap.numberOfTapsRequired = 3
        view.addGestureRecognizer(tripleTap)
        
        tapGesture.require(toFail: doubleTap)
        tapGesture.require(toFail: tripleTap)
        doubleTap.require(toFail: tripleTap)
    }
    
    
    
    // MARK: - Обработчики жестов
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        Task { @MainActor in
            viewModel.toggleSimulation()
            startRenderingIfNeeded()
        }
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        mtkView.isPaused = true
        
        Task { @MainActor in
            viewModel.resetParticleSystem()
            showRestartMessage()
            
            isFirstLayout = true
            view.setNeedsLayout()
            view.layoutIfNeeded()
        }
    }
    
    @objc private func handleTripleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        Task { @MainActor in
            viewModel.startLightningStorm()
            startRenderingIfNeeded()
        }
    }
    
    private func startRenderingIfNeeded() {
        mtkView.isPaused = false
    }
    
    // MARK: - Визуальная обратная связь
    
    private func showRestartMessage() {
        let label = UILabel()
        label.text = "Перезапуск системы..."
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        
        view.addSubview(label)
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
        
        UIView.animate(withDuration: 0.3) {
            label.alpha = 1
        } completion: { _ in
            UIView.animate(withDuration: 0.3, delay: 1.0) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }
    
    private func setupQualityUpgradeNotification() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleQualityUpgraded),
            name: .particleQualityUpgraded,
            object: nil
        )
    }
    
    @objc private func handleQualityUpgraded() {
        showQualityUpgradeAnimation()
    }
    
    private func showQualityUpgradeAnimation() {
        DispatchQueue.main.async {
            self.qualityUpgradeLabel?.removeFromSuperview()
            
            let label = UILabel()
            label.text = "Качество улучшено!"
            label.textAlignment = .center
            label.textColor = .systemGreen
            label.font = .systemFont(ofSize: 20, weight: .bold)
            label.alpha = 0
            label.translatesAutoresizingMaskIntoConstraints = false
            
            self.view.addSubview(label)
            self.qualityUpgradeLabel = label
            
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: self.view.centerXAnchor),
                label.topAnchor.constraint(equalTo: self.view.safeAreaLayoutGuide.topAnchor, constant: 50)
            ])
            
            UIView.animate(withDuration: 0.5, delay: 0, usingSpringWithDamping: 0.6, initialSpringVelocity: 0.8) {
                label.alpha = 1
                label.transform = CGAffineTransform(scaleX: 1.1, y: 1.1)
            } completion: { _ in
                UIView.animate(withDuration: 0.3) {
                    label.transform = .identity
                }
            }
            
            DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
                UIView.animate(withDuration: 0.5) {
                    label.alpha = 0
                } completion: { _ in
                    if self.qualityUpgradeLabel === label {
                        self.qualityUpgradeLabel = nil
                    }
                    label.removeFromSuperview()
                }
            }
        }
    }
    
    // MARK: - Деинициализация
    
    deinit {
        NotificationCenter.default.removeObserver(self)
        
        // Очищаем ресурсы при деините ViewController
        viewModel.cleanupAllResources()
    }
}
