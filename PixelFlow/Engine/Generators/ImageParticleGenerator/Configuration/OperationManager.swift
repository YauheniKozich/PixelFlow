//
//  OperationManager.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Менеджер асинхронных операций генерации частиц
//

import Foundation

/// Менеджер асинхронных операций генерации частиц
final class OperationManager: OperationManagerProtocol {

    // MARK: - Properties

    private let operationQueue: OperationQueue
    private let activeOperationsQueue = DispatchQueue(label: "activeOperations", attributes: .concurrent)
    private var activeOperations: Set<Operation> = []

    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(logger: LoggerProtocol) {
        self.logger = logger

        self.operationQueue = OperationQueue()
        self.operationQueue.name = "com.generation.operations"
        self.operationQueue.maxConcurrentOperationCount = OperationQueue.defaultMaxConcurrentOperationCount
        self.operationQueue.qualityOfService = .userInitiated

        logger.info("OperationManager initialized")
    }

    // MARK: - OperationManagerProtocol

    var maxConcurrentOperationCount: Int {
        get { operationQueue.maxConcurrentOperationCount }
        set { operationQueue.maxConcurrentOperationCount = newValue }
    }

    var qualityOfService: QualityOfService {
        get { operationQueue.qualityOfService }
        set { operationQueue.qualityOfService = newValue }
    }

    var name: String? {
        get { operationQueue.name }
        set { operationQueue.name = newValue }
    }

    var operationCount: Int {
        operationQueue.operationCount
    }

    var executingOperationsCount: Int {
        activeOperationsQueue.sync {
            activeOperations.count
        }
    }

    var hasActiveOperations: Bool {
        activeOperationsQueue.sync {
            !activeOperations.isEmpty
        }
    }

    func addOperation(_ operation: Operation) {
        activeOperationsQueue.async(flags: .barrier) {
            self.activeOperations.insert(operation)
        }

        // Настройка completion block для очистки
        let originalCompletion = operation.completionBlock
        operation.completionBlock = { [weak self, weak operation] in
            // Выполняем оригинальный completion block
            originalCompletion?()

            // Удаляем операцию из активных
            if let operation = operation {
                self?.removeOperation(operation)
            }
        }

        operationQueue.addOperation(operation)
        logger.debug("Added operation: \(operation.name ?? "unnamed")")
    }

    func cancelAllOperations() {
        activeOperationsQueue.sync {
            let operationsToCancel = activeOperations
            for operation in operationsToCancel {
                operation.cancel()
            }
        }

        operationQueue.cancelAllOperations()
        logger.info("Cancelled all operations")
    }

    // MARK: - Public Methods

    /// Выполняет асинхронную операцию и возвращает результат
    func execute<T: Sendable>(_ operation: @escaping () async throws -> T) async throws -> T {
        let operationWrapper = AsyncOperation { try await operation() }
        addOperation(operationWrapper)

        return try await withCheckedThrowingContinuation { continuation in
            operationWrapper.resultHandler = { result in
                switch result {
                case .success(let value):
                    continuation.resume(returning: value)
                case .failure(let error):
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    /// Ожидает завершения всех операций
    func waitUntilAllOperationsAreFinished() {
        operationQueue.waitUntilAllOperationsAreFinished()
    }

    /// Получает статистику операций
    func operationStats() -> OperationStats {
        let activeCount = activeOperationsQueue.sync {
            activeOperations.count
        }

        return OperationStats(
            queuedOperations: operationQueue.operationCount,
            activeOperations: activeCount,
            maxConcurrentOperations: operationQueue.maxConcurrentOperationCount,
            qualityOfService: operationQueue.qualityOfService
        )
    }

    // MARK: - Private Methods

    private func removeOperation(_ operation: Operation) {
        activeOperationsQueue.async(flags: .barrier) {
            self.activeOperations.remove(operation)
        }

        logger.debug("Removed operation: \(operation.name ?? "unnamed")")
    }
}

/// Статистика операций
struct OperationStats {
    let queuedOperations: Int
    let activeOperations: Int
    let maxConcurrentOperations: Int
    let qualityOfService: QualityOfService

    var description: String {
        """
        Queued: \(queuedOperations)
        Active: \(activeOperations)
        Max Concurrent: \(maxConcurrentOperations)
        QoS: \(qualityOfService)
        """
    }
}

/// Асинхронная операция-обертка
private class AsyncOperation<T: Sendable>: Operation, @unchecked Sendable {
    private let operationBlock: () async throws -> T
    private var executionTask: Task<T, Error>?

    private var hasResultBeenHandled = false
    private let resultHandlerLock = NSLock()

    var resultHandler: ((Result<T, Error>) -> Void)?

    init(operationBlock: @escaping () async throws -> T) {
        self.operationBlock = operationBlock
        super.init()
    }

    override func main() {
        if isCancelled {
            callResultHandlerOnce(with: .failure(OperationError.operationCancelled))
            return
        }

        executionTask = Task {
            do {
                let result = try await operationBlock()
                callResultHandlerOnce(with: .success(result))
                return result
            } catch {
                if !isCancelled {
                    callResultHandlerOnce(with: .failure(error))
                } else {
                    callResultHandlerOnce(with: .failure(OperationError.operationCancelled))
                }
                throw error
            }
        }
    }

    override func cancel() {
        super.cancel()
        executionTask?.cancel()
        callResultHandlerOnce(with: .failure(OperationError.operationCancelled))
    }

    private func callResultHandlerOnce(with result: Result<T, Error>) {
        resultHandlerLock.lock()
        defer { resultHandlerLock.unlock() }
        if !hasResultBeenHandled {
            hasResultBeenHandled = true
            resultHandler?(result)
        }
    }
}
