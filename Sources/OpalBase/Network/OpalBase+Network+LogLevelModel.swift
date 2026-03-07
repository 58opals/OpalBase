// OpalBase+Network+LogLevelModel.swift

import Foundation

extension _OpalBase.Network {
    public enum LogLevelModel: Sendable {
        case trace
        case debug
        case info
        case notice
        case warning
        case error
        case critical
    }
}
