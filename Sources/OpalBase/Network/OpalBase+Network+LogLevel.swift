// OpalBase+Network+LogLevel.swift

import Foundation

extension _OpalBase.Network {
    public enum LogLevel: Sendable {
        case trace
        case debug
        case info
        case notice
        case warning
        case error
        case critical
    }
}
