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
        _ = activeOperationsQueue.sync(flags: .barrier) {
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
        let resultGate = OperationResultGate<T>()
        operationWrapper.resultHandler = { result in
            resultGate.resolve(result)
        }

        return try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { continuation in
                resultGate.install(continuation)
                addOperation(operationWrapper)
            }
        } onCancel: {
            operationWrapper.cancel()
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
    private let stateLock = NSLock()
    private var executionTask: Task<T, Error>?
    private var isExecutingOperation = false
    private var isFinishedOperation = false
    private var isFinishing = false
    private var hasResultBeenHandled = false
    private let resultHandlerLock = NSLock()

    var resultHandler: ((Result<T, Error>) -> Void)?

    init(operationBlock: @escaping () async throws -> T) {
        self.operationBlock = operationBlock
        super.init()
    }

    override var isAsynchronous: Bool { true }

    override var isExecuting: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isExecutingOperation
    }

    override var isFinished: Bool {
        stateLock.lock()
        defer { stateLock.unlock() }
        return isFinishedOperation
    }

    override func start() {
        if isCancelled {
            callResultHandlerOnce(with: .failure(OperationError.operationCancelled))
            finish()
            return
        }

        guard transitionToExecuting() else {
            callResultHandlerOnce(with: .failure(OperationError.operationCancelled))
            finish()
            return
        }
        guard !isCancelled else {
            finish()
            return
        }
        let task = Task {
            let result: T
            do {
                guard !self.isCancelled else {
                    throw OperationError.operationCancelled
                }
                result = try await operationBlock()
                callResultHandlerOnce(with: .success(result))
            } catch {
                if !isCancelled {
                    callResultHandlerOnce(with: .failure(error))
                } else {
                    callResultHandlerOnce(with: .failure(OperationError.operationCancelled))
                }
                finish()
                throw error
            }
            finish()
            return result
        }

        stateLock.lock()
        executionTask = task
        let shouldCancel = isCancelled
        stateLock.unlock()
        if shouldCancel { task.cancel() }
    }

    override func cancel() {
        super.cancel()
        stateLock.lock()
        let task = executionTask
        let isRunning = isExecutingOperation
        stateLock.unlock()
        task?.cancel()
        callResultHandlerOnce(with: .failure(OperationError.operationCancelled))
        if !isRunning { finish() }
    }

    private func transitionToExecuting() -> Bool {
        stateLock.lock()
        guard !isFinishedOperation, !isFinishing, !isCancelled else {
            stateLock.unlock()
            return false
        }
        isFinishing = true
        stateLock.unlock()

        willChangeValue(forKey: "isExecuting")
        stateLock.lock()
        isExecutingOperation = true
        isFinishing = false
        stateLock.unlock()
        didChangeValue(forKey: "isExecuting")
        return true
    }

    private func finish() {
        stateLock.lock()
        guard !isFinishedOperation, !isFinishing else {
            stateLock.unlock()
            return
        }
        isFinishing = true
        let wasExecuting = isExecutingOperation
        stateLock.unlock()

        if wasExecuting { willChangeValue(forKey: "isExecuting") }
        willChangeValue(forKey: "isFinished")
        stateLock.lock()
        isExecutingOperation = false
        isFinishedOperation = true
        isFinishing = false
        stateLock.unlock()
        didChangeValue(forKey: "isFinished")
        if wasExecuting { didChangeValue(forKey: "isExecuting") }
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

private final class OperationResultGate<T> {
    private let lock = NSLock()
    private var continuation: CheckedContinuation<T, Error>?
    private var pendingResult: Result<T, Error>?

    func install(_ continuation: CheckedContinuation<T, Error>) {
        lock.lock()
        let result = pendingResult
        if result == nil { self.continuation = continuation }
        lock.unlock()

        if let result { resume(continuation, with: result) }
    }

    func resolve(_ result: Result<T, Error>) {
        lock.lock()
        guard pendingResult == nil else {
            lock.unlock()
            return
        }
        pendingResult = result
        let continuation = self.continuation
        self.continuation = nil
        lock.unlock()

        if let continuation { resume(continuation, with: result) }
    }

    private func resume(_ continuation: CheckedContinuation<T, Error>, with result: Result<T, Error>) {
        switch result {
        case .success(let value): continuation.resume(returning: value)
        case .failure(let error): continuation.resume(throwing: error)
        }
    }
}
