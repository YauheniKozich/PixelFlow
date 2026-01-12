//
//  Logger.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 31.10.25.
//  Утилита логирования для структурированного логирования во всем приложении
//

import Foundation

enum LogLevel: String {
    case debug = "DEBUG"
    case info = "INFO"
    case warning = "WARNING"
    case error = "ERROR"
}

final class Logger {
    static let shared = Logger()

    #if DEBUG
    private let isLoggingEnabled = true
    #else
    private let isLoggingEnabled = false
    #endif

    private init() {}

    func log(_ message: String, level: LogLevel = .info, file: String = #file, function: String = #function, line: Int = #line) {
        guard isLoggingEnabled else { return }

        let timestamp = Date().formatted(.iso8601.time(includingFractionalSeconds: true))
        let filename = (file as NSString).lastPathComponent as String
        let logMessage = "[\(timestamp)] [\(level.rawValue)] [\(filename):\(line)] \(function): \(message)"

        print(logMessage)
    }

    func debug(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .debug, file: file, function: function, line: line)
    }

    func info(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .info, file: file, function: function, line: line)
    }

    func warning(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .warning, file: file, function: function, line: line)
    }

    func error(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .error, file: file, function: function, line: line)
    }
}