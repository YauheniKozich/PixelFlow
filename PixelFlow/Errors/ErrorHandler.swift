//
//  ErrorHandler.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 20.01.26.
//

import UIKit

/// Стратегии восстановления после ошибок
public enum RecoveryStrategy {
    /// Повторить операцию указанное количество раз
    case retry(count: Int)

    /// Использовать резервный вариант
    case fallback

    /// Показать пользователю сообщение
    case showUserMessage(String, style: UIAlertController.Style = .alert)

    /// Показать toast уведомление
    case showToast(String, duration: TimeInterval = 3.0)

    /// Игнорировать ошибку
    case ignore

    /// Завершить приложение (только для критичных ошибок)
    case terminate

    /// Кастомная стратегия с блоком
    case custom((Error, String?) -> Void)
}

/// Протокол для централизованной обработки ошибок
public protocol ErrorHandlerProtocol: AnyObject {
    /// Обработать восстанавливаемую ошибку
    func handle(_ error: Error, context: String?, recovery: RecoveryStrategy?)

    /// Обработать критичную ошибку (приводит к завершению)
    func handleFatal(_ error: Error, context: String?)
}

/// Базовая реализация обработчика ошибок
public final class ErrorHandler: ErrorHandlerProtocol {

    // MARK: - Dependencies

    private let logger: LoggerProtocol
    private let analyticsService: AnalyticsServiceProtocol?

    // MARK: - Configuration

    /// Максимальное количество retry попыток
    private let maxRetryCount = 3

    /// Очередь для выполнения recovery операций
    private let recoveryQueue = DispatchQueue(label: "com.pixelflow.error.recovery", qos: .userInitiated)

    // MARK: - Initialization

    public init(logger: LoggerProtocol = Logger.shared,
                analyticsService: AnalyticsServiceProtocol? = nil) {
        self.logger = logger
        self.analyticsService = analyticsService

        logger.info("ErrorHandler initialized")
    }

    // MARK: - ErrorHandlerProtocol

    public func handle(_ error: Error, context: String?, recovery: RecoveryStrategy? = nil) {
        // Логирование ошибки
        let contextInfo = context.map { " [\($0)]" } ?? ""
        logger.error("Handled error: \(error.localizedDescription)\(contextInfo)")

        // Отправка в аналитику
        analyticsService?.trackError(error, context: context)

        // Применение стратегии восстановления
        if let recovery = recovery {
            applyRecoveryStrategy(recovery, for: error, context: context)
        }
    }

    public func handleFatal(_ error: Error, context: String?) {
        let contextInfo = context.map { " [\($0)]" } ?? ""
        logger.error("FATAL ERROR: \(error.localizedDescription)\(contextInfo)")

        // Отправка критичной ошибки в аналитику
        analyticsService?.trackFatalError(error, context: context)

        // Показать пользователю критическую ошибку
        showCriticalErrorAlert(error: error, context: context)

        // В production можно отправить crash report
        #if DEBUG
        fatalError("Critical error: \(error.localizedDescription)")
        #else
        // В релизе лучшее решение - перезапустить приложение или показать recovery UI
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            exit(0)
        }
        #endif
    }

    // MARK: - Private Methods

    private func applyRecoveryStrategy(_ strategy: RecoveryStrategy, for error: Error, context: String?) {
        recoveryQueue.async {
            switch strategy {
            case .retry(let count):
                self.handleRetry(count: count, error: error, context: context)

            case .fallback:
                self.handleFallback(error: error, context: context)

            case .showUserMessage(let message, let style):
                self.showUserAlert(message: message, style: style, error: error)

            case .showToast(let message, let duration):
                self.showToast(message: message, duration: duration)

            case .ignore:
                // Ничего не делать
                break

            case .terminate:
                self.handleFatal(error, context: context)

            case .custom(let handler):
                handler(error, context)
            }
        }
    }

    private func handleRetry(count: Int, error: Error, context: String?) {
        guard count > 0 && count <= maxRetryCount else {
            logger.warning("Invalid retry count: \(count)")
            return
        }

        logger.info("Retrying operation \(maxRetryCount - count + 1)/\(maxRetryCount)")

        // Здесь можно реализовать логику retry с exponential backoff
        // Для демонстрации просто логируем
        logger.debug("Would retry operation with exponential backoff")
    }

    private func handleFallback(error: Error, context: String?) {
        logger.info("Switching to fallback mode for error: \(error.localizedDescription)")

        // Здесь можно реализовать fallback логику
        // Например, переключение на CPU вместо GPU, или упрощенную версию алгоритма
        logger.debug("Would activate fallback implementation")
    }

    private func showUserAlert(message: String, style: UIAlertController.Style, error: Error) {
        DispatchQueue.main.async {
            guard let topVC = UIApplication.shared.topViewController() else {
                self.logger.warning("Cannot show alert - no top view controller")
                return
            }

            let alert = UIAlertController(title: "Ошибка",
                                        message: message,
                                        preferredStyle: style)

            alert.addAction(UIAlertAction(title: "OK", style: .default))

            topVC.present(alert, animated: true)
        }
    }

    private func showToast(message: String, duration: TimeInterval) {
        DispatchQueue.main.async {
            // Простая реализация toast через UILabel
            guard let window = UIApplication.shared.keyWindow else { return }

            let toastLabel = UILabel()
            toastLabel.text = message
            toastLabel.textAlignment = .center
            toastLabel.backgroundColor = UIColor.black.withAlphaComponent(0.8)
            toastLabel.textColor = .white
            toastLabel.font = .systemFont(ofSize: 14)
            toastLabel.numberOfLines = 0
            toastLabel.layer.cornerRadius = 8
            toastLabel.clipsToBounds = true

            let padding: CGFloat = 16
            let maxWidth = window.bounds.width - 32
            let size = toastLabel.sizeThatFits(CGSize(width: maxWidth - padding * 2, height: .greatestFiniteMagnitude))

            toastLabel.frame = CGRect(x: 16,
                                    y: window.bounds.height - 100,
                                    width: min(size.width + padding * 2, maxWidth),
                                    height: size.height + padding)

            window.addSubview(toastLabel)

            UIView.animate(withDuration: 0.3, delay: duration, options: .curveEaseOut) {
                toastLabel.alpha = 0
            } completion: { _ in
                toastLabel.removeFromSuperview()
            }
        }
    }

    private func showCriticalErrorAlert(error: Error, context: String?) {
        DispatchQueue.main.async {
            let message = """
            Произошла критическая ошибка.
            Приложение будет перезапущено.

            Ошибка: \(error.localizedDescription)
            \(context.map { "Контекст: \($0)" } ?? "")
            """

            let alert = UIAlertController(title: "Критическая ошибка",
                                        message: message,
                                        preferredStyle: .alert)

            alert.addAction(UIAlertAction(title: "OK", style: .destructive) { _ in
                // Завершить приложение
                exit(0)
            })

            if let topVC = UIApplication.shared.topViewController() {
                topVC.present(alert, animated: true)
            }
        }
    }
}

// MARK: - Analytics Service Protocol

/// Протокол для сервиса аналитики (опциональный)
public protocol AnalyticsServiceProtocol: AnyObject {
    func trackError(_ error: Error, context: String?)
    func trackFatalError(_ error: Error, context: String?)
}

// MARK: - UIApplication Extension

private extension UIApplication {
    /// Получить верхний view controller в иерархии
    func topViewController(_ base: UIViewController? = nil) -> UIViewController? {
        let base = base ?? keyWindow?.rootViewController
        if let nav = base as? UINavigationController {
            return topViewController(nav.visibleViewController)
        }
        if let tab = base as? UITabBarController {
            return topViewController(tab.selectedViewController)
        }
        if let presented = base?.presentedViewController {
            return topViewController(presented)
        }
        return base
    }

    /// Получить key window (для iOS 13+)
    var keyWindow: UIWindow? {
        if #available(iOS 13.0, *) {
            return connectedScenes
                .compactMap { $0 as? UIWindowScene }
                .flatMap { $0.windows }
                .first { $0.isKeyWindow }
        } else {
            return UIApplication.shared.keyWindow
        }
    }
}
