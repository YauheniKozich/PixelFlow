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
    case trace = "TRACE"
}

public final class Logger {
    public static let shared = Logger()
    
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
    
    func trace(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
        log(message, level: .trace, file: file, function: function, line: line)
    }
}

// MARK: - LoggerProtocol Conformance

extension Logger: LoggerProtocol {
    public func info(_ message: String) {
        log(message, level: .info, file: #file, function: #function, line: #line)
    }
    
    public func warning(_ message: String) {
        log(message, level: .warning, file: #file, function: #function, line: #line)
    }
    
    public func error(_ message: String) {
        log(message, level: .error, file: #file, function: #function, line: #line)
    }
    
    public func debug(_ message: String) {
        log(message, level: .debug, file: #file, function: #function, line: #line)
    }
    
    public func trace(_ message: String) {
        log(message, level: .trace, file: #file, function: #function, line: #line)
    }
}
