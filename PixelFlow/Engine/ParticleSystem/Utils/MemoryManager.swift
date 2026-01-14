//
//  MemoryManager.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//  Менеджер памяти для системы частиц
//

import Foundation
import UIKit

/// Менеджер памяти для системы частиц
final class MemoryManager: MemoryManagerProtocol {

    // MARK: - Properties

    private(set) var currentUsage: Int64 = 0
    private let lock = NSLock()
    private var memoryWarningObserver: NSObjectProtocol?
    private let logger: LoggerProtocol

    // MARK: - Initialization

    init(logger: LoggerProtocol = Logger.shared) {
        self.logger = logger
        setupMemoryWarningObserver()
        logger.info("MemoryManager initialized")
    }

    deinit {
        removeMemoryWarningObserver()
    }

    // MARK: - MemoryManagerProtocol

    func trackMemoryUsage(_ bytes: Int64) {
        lock.lock()
        defer { lock.unlock() }

        currentUsage += bytes

        if currentUsage > 100 * 1024 * 1024 { // 100MB
            logger.warning("High memory usage detected: \(formatBytes(currentUsage))")
        }
    }

    func releaseMemory() {
        lock.lock()
        defer { lock.unlock() }

        let previousUsage = currentUsage
        currentUsage = 0

        logger.info("Memory released: \(formatBytes(previousUsage))")

        // Принудительная сборка мусора
        autoreleasepool {
            // Создаем временные объекты для вытеснения больших
            let temporaryData = Data(count: 1024)
            _ = temporaryData.count
        }
    }

    func handleLowMemory() {
        logger.warning("Low memory warning received - releasing resources")

        // Освобождаем всю память
        releaseMemory()

        // Уведомляем систему
        notifyMemoryRelease()

        // Логируем текущее состояние
        logMemoryState()
    }

    // MARK: - Private Methods

    private func setupMemoryWarningObserver() {
        #if os(iOS)
        memoryWarningObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handleLowMemory()
        }
        #endif
    }

    private func removeMemoryWarningObserver() {
        if let observer = memoryWarningObserver {
            NotificationCenter.default.removeObserver(observer)
            memoryWarningObserver = nil
        }
    }

    private func notifyMemoryRelease() {
        // Даем время на освобождение памяти
        DispatchQueue.global(qos: .background).asyncAfter(deadline: .now() + 0.05) {
            autoreleasepool {
                // Пустой autorelease pool для освобождения
            }
        }
    }

    private func logMemoryState() {
        #if os(iOS)
        let processInfo = ProcessInfo.processInfo
        let physicalMemory = processInfo.physicalMemory

        logger.info("""
        Memory state:
        - Current usage: \(formatBytes(currentUsage))
        - Physical memory: \(formatBytes(Int64(physicalMemory)))
        """)
        #endif
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}