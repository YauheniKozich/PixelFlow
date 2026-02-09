import UIKit

// MARK: - View Controller

final class ViewController: UIViewController, ParticleSystemLifecycleHandling {
    
    // MARK: - Constants
    
    private enum Constants {
        static let qualityLabelFontSize: CGFloat = 20
        static let restartLabelFontSize: CGFloat = 18
        static let qualityLabelTopOffset: CGFloat = 50
        static let fadeInDuration: TimeInterval = 0.3
        static let fadeOutDuration: TimeInterval = 0.3
        static let fadeOutDelay: TimeInterval = 1.0
        static let qualityAnimationDuration: TimeInterval = 0.5
        static let qualitySpringDamping: CGFloat = 0.6
        static let qualitySpringVelocity: CGFloat = 0.8
        static let qualityScaleTransform: CGFloat = 1.1
        static let qualityLabelDismissDelay: TimeInterval = 3.0
        static let qualityFadeDuration: TimeInterval = 0.5
    }
    
    private enum Messages {
        static let restart = "Перезапуск системы..."
        static let qualityUpgrade = "HQ доступно"
    }
    
    // MARK: - Properties
    
    private let viewModel: ParticleViewModel
    private var renderView: RenderView?
    private var qualityUpgradeLabel: UILabel?
    private var restartMessageLabel: UILabel?
    private var isFirstLayout = true
    private var memoryWarningObserver: NSObjectProtocol?
    
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
        setupView()
        setupRenderView()
        setupGestures()
        setupViewModelCallbacks()
        setupMemoryWarningObserver()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateRenderViewLayout()
        handleFirstLayout()
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
    
    deinit {
        cleanupObservers()
    }
    
    // MARK: - Setup
    
    private func setupView() {
        view.backgroundColor = .black
    }
    
    private func setupRenderView() {
        let viewInstance = viewModel.makeRenderView(frame: view.bounds)
        renderView = viewInstance
        
        guard let renderUIView = viewInstance as? UIView else { return }
        view.addSubview(renderUIView)
    }
    
    private func setupViewModelCallbacks() {
        viewModel.onQualityUpgraded = { [weak self] in
            self?.showQualityUpgradeAnimation()
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
    
    private func cleanupObservers() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }
    
    // MARK: - Layout
    
    private func updateRenderViewLayout() {
        let scale = traitCollection.displayScale
        viewModel.updateRenderViewLayout(frame: view.bounds, scale: scale)
    }
    
    private func handleFirstLayout() {
        guard isFirstLayout else { return }
        guard view.bounds.size != .zero else { return }
        
        isFirstLayout = false
        initializeParticleSystem()
    }
    
    private func initializeParticleSystem() {
        Task { [weak self] in
            guard let self else { return }
            guard !self.viewModel.isConfigured else { return }
            guard let renderView = self.renderView else { return }
            
            self.viewModel.setImageDisplayMode(.fit)
            
            if await self.viewModel.createSystem(in: renderView) {
                self.activateGestures()
            }
        }
    }
    
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
    
    // MARK: - Gesture Setup
    
    private func setupGestures() {
        let tapGesture = createTapGesture()
        let doubleTap = createDoubleTapGesture()
        let tripleTap = createTripleTapGesture()
        
        configureGestureRecognizers(
            tap: tapGesture,
            doubleTap: doubleTap,
            tripleTap: tripleTap
        )
        
        addGestureRecognizers(
            tap: tapGesture,
            doubleTap: doubleTap,
            tripleTap: tripleTap
        )
    }
    
    private func createTapGesture() -> UITapGestureRecognizer {
        return UITapGestureRecognizer(target: self, action: #selector(handleTap))
    }
    
    private func createDoubleTapGesture() -> UITapGestureRecognizer {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        gesture.numberOfTapsRequired = 2
        return gesture
    }
    
    private func createTripleTapGesture() -> UITapGestureRecognizer {
        let gesture = UITapGestureRecognizer(target: self, action: #selector(handleTripleTap))
        gesture.numberOfTapsRequired = 3
        return gesture
    }
    
    private func configureGestureRecognizers(
        tap: UITapGestureRecognizer,
        doubleTap: UITapGestureRecognizer,
        tripleTap: UITapGestureRecognizer
    ) {
        tap.require(toFail: doubleTap)
        tap.require(toFail: tripleTap)
        doubleTap.require(toFail: tripleTap)
    }
    
    private func addGestureRecognizers(
        tap: UITapGestureRecognizer,
        doubleTap: UITapGestureRecognizer,
        tripleTap: UITapGestureRecognizer
    ) {
        view.addGestureRecognizer(tap)
        view.addGestureRecognizer(doubleTap)
        view.addGestureRecognizer(tripleTap)
    }
    
    // MARK: - Gesture Handlers
    
    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        viewModel.toggleSimulation()
        startRendering()
    }
    
    @objc private func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        performSystemReset()
    }
    
    @objc private func handleTripleTap(_ gesture: UITapGestureRecognizer) {
        guard gesture.state == .ended else { return }
        
        viewModel.startLightningStorm()
        startRendering()
    }
    
    private func performSystemReset() {
        viewModel.pauseRendering()
        viewModel.resetParticleSystem()
        showRestartMessage()
        resetLayout()
    }
    
    private func resetLayout() {
        isFirstLayout = true
        view.setNeedsLayout()
        view.layoutIfNeeded()
    }
    
    private func startRendering() {
        renderView?.setNeedsDisplay()
    }
    
    // MARK: - Visual Feedback
    
    private func showRestartMessage() {
        removeExistingRestartLabel()
        
        let label = createRestartLabel()
        addRestartLabel(label)
        animateRestartLabel(label)
    }
    
    private func removeExistingRestartLabel() {
        restartMessageLabel?.removeFromSuperview()
    }
    
    private func createRestartLabel() -> UILabel {
        let label = UILabel()
        label.text = Messages.restart
        label.textAlignment = .center
        label.textColor = .white
        label.font = .systemFont(ofSize: Constants.restartLabelFontSize, weight: .semibold)
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func addRestartLabel(_ label: UILabel) {
        view.addSubview(label)
        restartMessageLabel = label
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.centerYAnchor.constraint(equalTo: view.centerYAnchor)
        ])
    }
    
    private func animateRestartLabel(_ label: UILabel) {
        UIView.animate(withDuration: Constants.fadeInDuration) {
            label.alpha = 1
        } completion: { [weak self] _ in
            self?.scheduleRestartLabelDismissal(label)
        }
    }
    
    private func scheduleRestartLabelDismissal(_ label: UILabel) {
        UIView.animate(
            withDuration: Constants.fadeOutDuration,
            delay: Constants.fadeOutDelay
        ) {
            label.alpha = 0
        } completion: { [weak self] _ in
            self?.cleanupRestartLabel(label)
        }
    }
    
    private func cleanupRestartLabel(_ label: UILabel) {
        if restartMessageLabel === label {
            restartMessageLabel = nil
        }
        label.removeFromSuperview()
    }
    
    // MARK: - Quality Upgrade Animation
    
    private func showQualityUpgradeAnimation() {
        removeExistingQualityLabel()
        
        let label = createQualityLabel()
        addQualityLabel(label)
        animateQualityLabel(label)
    }
    
    private func removeExistingQualityLabel() {
        qualityUpgradeLabel?.removeFromSuperview()
    }
    
    private func createQualityLabel() -> UILabel {
        let label = UILabel()
        label.text = Messages.qualityUpgrade
        label.textAlignment = .center
        label.textColor = .systemGreen
        label.font = .systemFont(ofSize: Constants.qualityLabelFontSize, weight: .bold)
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }
    
    private func addQualityLabel(_ label: UILabel) {
        view.addSubview(label)
        qualityUpgradeLabel = label
        
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.topAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.topAnchor,
                constant: Constants.qualityLabelTopOffset
            )
        ])
    }
    
    private func animateQualityLabel(_ label: UILabel) {
        animateQualityLabelEntrance(label)
        scheduleQualityLabelDismissal(label)
    }
    
    private func animateQualityLabelEntrance(_ label: UILabel) {
        UIView.animate(
            withDuration: Constants.qualityAnimationDuration,
            delay: 0,
            usingSpringWithDamping: Constants.qualitySpringDamping,
            initialSpringVelocity: Constants.qualitySpringVelocity
        ) {
            label.alpha = 1
            label.transform = CGAffineTransform(
                scaleX: Constants.qualityScaleTransform,
                y: Constants.qualityScaleTransform
            )
        } completion: { _ in
            self.normalizeQualityLabelTransform(label)
        }
    }
    
    private func normalizeQualityLabelTransform(_ label: UILabel) {
        UIView.animate(withDuration: Constants.fadeInDuration) {
            label.transform = .identity
        }
    }
    
    private func scheduleQualityLabelDismissal(_ label: UILabel) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.qualityLabelDismissDelay) { [weak self] in
            self?.dismissQualityLabel(label)
        }
    }
    
    private func dismissQualityLabel(_ label: UILabel) {
        UIView.animate(withDuration: Constants.qualityFadeDuration) {
            label.alpha = 0
        } completion: { [weak self] _ in
            self?.cleanupQualityLabel(label)
        }
    }
    
    private func cleanupQualityLabel(_ label: UILabel) {
        if qualityUpgradeLabel === label {
            qualityUpgradeLabel = nil
        }
        label.removeFromSuperview()
    }
}
