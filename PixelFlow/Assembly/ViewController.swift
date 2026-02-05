import UIKit


class ViewController: UIViewController, ParticleSystemLifecycleHandling {

    // MARK: - Свойства

    private let viewModel: ParticleViewModel
    private var renderView: RenderView?
    private var qualityUpgradeLabel: UILabel?
    private var restartMessageLabel: UILabel?
    private var isFirstLayout = true
    private var memoryWarningObserver: NSObjectProtocol?
  

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
        let viewInstance = viewModel.makeRenderView(frame: view.bounds)
        renderView = viewInstance
        guard let renderUIView = viewInstance as? UIView else { return }
        view.addSubview(renderUIView)
        setupGestures()
        setupViewModelCallbacks()
        setupMemoryWarningObserver()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let scale = traitCollection.displayScale
        viewModel.updateRenderViewLayout(
            frame: view.bounds,
            scale: scale
        )
        
        guard isFirstLayout else { return }
        guard view.bounds.size != .zero else { return }
        isFirstLayout = false
        
        Task { [weak self] in
            guard let self else { return }
            if self.viewModel.isConfigured { return }
            guard let renderView = self.renderView else { return }
            if await self.viewModel.createSystem(in: renderView) {
                self.activateGestures()
                
            }
        }
    }
    
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        viewModel.pauseRendering()
    }
    
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        viewModel.cleanupAllResources()
    }
    
    override var prefersStatusBarHidden: Bool { true }

    // MARK: - Настройка MetalView

    
    private func activateGestures() {
        renderView?.isUserInteractionEnabled = true
    }

    // MARK: - App Lifecycle Forwarding

    func handleWillResignActive() {
        viewModel.handleWillResignActive()
    }

    func handleDidBecomeActive() {
        viewModel.handleDidBecomeActive()
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
        viewModel.pauseRendering()
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
        renderView?.setNeedsDisplay()
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

    private func setupViewModelCallbacks() {
        viewModel.onQualityUpgraded = { [weak self] in
            guard let self else { return }
            self.showQualityUpgradeAnimation()
        }
    }

    private func setupMemoryWarningObserver() {
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.viewModel.handleLowMemory()
            }
        }
    }

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
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
}
