//
//  CacheManager.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 11.01.26.
//

import Foundation
import CryptoKit

/// Менеджер кэширования результатов генерации частиц
final class DefaultCacheManager: CacheManager, CacheManagerProtocol {

    private let cacheDirectory: URL
    private var maxCacheSize: Int // в байтах
    private let queue = DispatchQueue(label: "com.particlegen.cachemanager", attributes: .concurrent)

    private var cacheIndex: [String: CacheEntry] = [:]
    private var currentCacheSize: Int = 0

    struct CacheEntry: Codable {
        let key: String
        let fileName: String
        let size: Int
        let createdAt: Date
        var lastAccessed: Date
    }

    init(cacheSizeLimit: Int = 100 * 1024 * 1024) { // 100MB по умолчанию
        self.maxCacheSize = cacheSizeLimit

        // Создаем директорию кэша
        let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheDirectory = cachesDir.appendingPathComponent("ParticleGenerator", isDirectory: true)

        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)

        // Загружаем индекс кэша
        loadCacheIndex()
    }

    func cache<T: Codable>(_ value: T, for key: String) throws {
        try queue.sync(flags: .barrier) {
            let fileName = self.generateFileName(for: key)
            let fileURL = cacheDirectory.appendingPathComponent(fileName)

            // Сериализуем данные
            let data = try JSONEncoder().encode(value)

            // Проверяем размер
            if data.count > maxCacheSize / 4 { // Не кэшируем слишком большие объекты
                return
            }

            // Удаляем старый файл если существует
            if let oldEntry = cacheIndex[key] {
                try? FileManager.default.removeItem(at: cacheDirectory.appendingPathComponent(oldEntry.fileName))
                currentCacheSize -= oldEntry.size
            }

            // Очищаем кэш если необходимо
            try cleanupIfNeeded(additionalSize: data.count)

            // Записываем файл
            try data.write(to: fileURL, options: .atomic)

            // Обновляем индекс
            let entry = CacheEntry(
                key: key,
                fileName: fileName,
                size: data.count,
                createdAt: Date(),
                lastAccessed: Date()
            )

            cacheIndex[key] = entry
            currentCacheSize += data.count

            // Сохраняем индекс
            try saveCacheIndex()
        }
    }

    func retrieve<T: Codable>(_ type: T.Type, for key: String) throws -> T? {
        // Используем barrier для записи, чтобы избежать race condition при обновлении индекса
        return queue.sync(flags: .barrier) {
            guard let entry = cacheIndex[key] else { return nil }

            let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)

            // Проверяем существование файла
            guard FileManager.default.fileExists(atPath: fileURL.path) else {
                // Удаляем поврежденную запись из индекса
                cacheIndex.removeValue(forKey: key)
                currentCacheSize -= entry.size
                try? saveCacheIndex()
                return nil
            }

            do {
                // Читаем данные
                let data = try Data(contentsOf: fileURL)

                // Обновляем время последнего доступа (защищено barrier)
                var updatedEntry = entry
                updatedEntry.lastAccessed = Date()
                cacheIndex[key] = updatedEntry

                // Пытаемся сохранить индекс, но не прерываем выполнение при ошибке
                try? saveCacheIndex()

                // Десериализуем
                return try JSONDecoder().decode(type, from: data)
            } catch {
                // Если файл поврежден, удаляем запись
                cacheIndex.removeValue(forKey: key)
                currentCacheSize -= entry.size
                try? FileManager.default.removeItem(at: fileURL)
                try? saveCacheIndex()
                return nil
            }
        }
    }

    func clear() {
        queue.sync(flags: .barrier) {
            // Удаляем все файлы кэша
            for entry in cacheIndex.values {
                let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
                try? FileManager.default.removeItem(at: fileURL)
            }

            // Очищаем индекс
            cacheIndex.removeAll()
            currentCacheSize = 0

            // Сохраняем пустой индекс
            try? saveCacheIndex()
        }
    }

    // MARK: - CacheManagerProtocol

    var size: Int64 {
        queue.sync { Int64(currentCacheSize) }
    }

    var sizeLimit: Int64 {
        get { queue.sync { Int64(maxCacheSize) } }
        set { queue.sync(flags: .barrier) { maxCacheSize = Int(newValue) } }
    }

    var count: Int {
        queue.sync { cacheIndex.count }
    }

    func contains(key: String) -> Bool {
        queue.sync { cacheIndex[key] != nil }
    }

    // MARK: - Private Methods

    private func generateFileName(for key: String) -> String {
        let hash = SHA256.hash(data: Data(key.utf8))
        return hash.compactMap { String(format: "%02x", $0) }.joined() + ".cache"
    }

    private func loadCacheIndex() {
        let indexURL = cacheDirectory.appendingPathComponent("cache_index.json")

        guard let data = try? Data(contentsOf: indexURL),
              let entries = try? JSONDecoder().decode([String: CacheEntry].self, from: data) else {
            return
        }

        cacheIndex = entries
        currentCacheSize = entries.values.reduce(0) { $0 + $1.size }
    }

    private func saveCacheIndex() throws {
        let indexURL = cacheDirectory.appendingPathComponent("cache_index.json")
        let data = try JSONEncoder().encode(cacheIndex)
        try data.write(to: indexURL, options: .atomic)
    }

    private func cleanupIfNeeded(additionalSize: Int) throws {
        guard currentCacheSize + additionalSize > maxCacheSize else { return }

        // Сортируем по времени последнего доступа (старые сначала)
        let sortedEntries = cacheIndex.values.sorted { $0.lastAccessed < $1.lastAccessed }

        var sizeToFree = currentCacheSize + additionalSize - maxCacheSize
        var entriesToRemove: [String] = []

        for entry in sortedEntries {
            guard sizeToFree > 0 else { break }

            // Удаляем файл
            let fileURL = cacheDirectory.appendingPathComponent(entry.fileName)
            try? FileManager.default.removeItem(at: fileURL)

            // Запоминаем ключи для удаления
            entriesToRemove.append(entry.key)
            currentCacheSize -= entry.size
            sizeToFree -= entry.size
        }

        // Удаляем из индекса все записи разом
        for key in entriesToRemove {
            cacheIndex.removeValue(forKey: key)
        }
    }
}

// MARK: - Memory Cache

/// Памятный кэш для часто используемых данных
final class MemoryCache<Key: Hashable, Value> {
    private let cache = NSCache<NSString, CacheWrapper>()
    private let keyFormatter = NumberFormatter()
    private let queue = DispatchQueue(label: "com.particlegen.memorycache", attributes: .concurrent)

    private class CacheWrapper {
        let value: Value
        let timestamp: Date

        init(_ value: Value) {
            self.value = value
            self.timestamp = Date()
        }
    }

    func set(_ value: Value, for key: Key) {
        queue.async(flags: .barrier) {
            let wrapper = CacheWrapper(value)
            let keyString = String(describing: key)
            self.cache.setObject(wrapper, forKey: NSString(string: keyString))
        }
    }

    func get(for key: Key) -> Value? {
        queue.sync {
            let keyString = String(describing: key)
            guard let wrapper = cache.object(forKey: NSString(string: keyString)) else {
                return nil
            }
            return wrapper.value
        }
    }

    func remove(for key: Key) {
        queue.async(flags: .barrier) {
            let keyString = String(describing: key)
            self.cache.removeObject(forKey: NSString(string: keyString))
        }
    }

    func clear() {
        queue.async(flags: .barrier) {
            self.cache.removeAllObjects()
        }
    }
}
