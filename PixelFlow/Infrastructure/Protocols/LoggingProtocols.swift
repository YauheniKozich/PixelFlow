//
//  LoggingProtocols.swift
//  PixelFlow
//
//  Created by Yauheni Kozich on 05.02.26.
//

import Foundation

/// Протокол для службы логирования
public protocol LoggerProtocol: Sendable {
    /// Логирует информационное сообщение
    func info(_ message: String)

    /// Логирует предупреждение
    func warning(_ message: String)

    /// Логирует ошибку
    func error(_ message: String)

    /// Логирует отладочное сообщение
    func debug(_ message: String)
}
