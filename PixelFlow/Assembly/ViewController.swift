import UIKit
import MetalKit

class ViewController: UIViewController {

    // MARK: - Свойства

    lazy var mtkView: MTKView = {
        let view = MTKView(frame: self.view.bounds, device: self.device)
        view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        view.colorPixelFormat = .bgra8Unorm_srgb
        view.framebufferOnly = true
        view.preferredFramesPerSecond = 60
        view.isPaused = true
        view.enableSetNeedsDisplay = false
        self.view.addSubview(view)
        return view
    }()
    private let viewModel: ParticleViewModel
    private let device: MTLDevice
    private var qualityUpgradeLabel: UILabel?
    private var restartMessageLabel: UILabel?
    private var isFirstLayout = true
    private var qualityUpgradeObserver: NSObjectProtocol?

    // MARK: - Инициализация

    init(viewModel: ParticleViewModel) {
        self.viewModel = viewModel

        guard let device = resolve(MTLDevice.self) else {
            fatalError("MTLDevice not available in DI container")
        }
        self.device = device

        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // MARK: - Жизненный цикл
    
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        // setupMetalView() больше не требуется, инициализация через lazy var
        setupGestures()
        setupQualityUpgradeNotification()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        mtkView.frame = view.bounds
        
        guard isFirstLayout else { return }
        isFirstLayout = false
        
        Task { @MainActor in
            if viewModel.isConfigured { return }
            if await viewModel.createSystem(in: mtkView) {
                viewModel.initializeWithFastPreview()
                viewModel.startSimulation()
                startRendering()
                activateGestures()
            }
        }
    }
    
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        startRendering()
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        mtkView.isPaused = true
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        Task { @MainActor in
            viewModel.cleanupAllResources()
        }
    }
    
    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Настройка MetalView

    
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
        viewModel.toggleSimulation()
        startRendering()
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        mtkView.isPaused = true
        viewModel.resetParticleSystem()
        showRestartMessage()
        isFirstLayout = true
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    @objc private func handleTripleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        viewModel.startLightningStorm()
        startRendering()
    }
    
    private func startRendering() {
        mtkView.isPaused = false
    }

    // MARK: - Визуальная обратная связь
    
    private func showRestartMessage() {
        restartMessageLabel?.removeFromSuperview()
        
        let label = UILabel()
        label.text = "Перезапуск системы..."
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: 18, weight: .semibold)
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        restartMessageLabel = label
        
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
                if self.restartMessageLabel === label {
                    self.restartMessageLabel = nil
                }
                label.removeFromSuperview()
            }
        }
    }
    
    private func setupQualityUpgradeNotification() {
        qualityUpgradeObserver = NotificationCenter.default.addObserver(
            forName: .particleQualityUpgraded,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in
                self.showQualityUpgradeAnimation()
            }
        }
    }
    
    @MainActor
    private func showQualityUpgradeAnimation() {
        qualityUpgradeLabel?.removeFromSuperview()
        
        let label = UILabel()
        label.text = "Качество улучшено!"
        label.textAlignment = .center
        label.textColor = .systemGreen
        label.font = .systemFont(ofSize: 20, weight: .bold)
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(label)
        qualityUpgradeLabel = label
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor, constant: 50)
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
    
    // MARK: - Деинициализация
    
    deinit {
        if let observer = qualityUpgradeObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
