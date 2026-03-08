// OpalBase+Network+DiagnosticsSnapshot~Fulcrum.swift

import SwiftFulcrum

extension _OpalBase.Network.DiagnosticsSnapshot {
    init(_ snapshot: SwiftFulcrum.Client.Diagnostics.Snapshot) {
        self.init(
            reconnectionAttemptCount: snapshot.reconnectAttempts,
            reconnectSuccesses: snapshot.reconnectSuccesses,
            inflightUnaryCallCount: snapshot.inflightUnaryCallCount,
            activeSubscriptionCount: snapshot.activeSubscriptionCount
        )
    }
}

extension _OpalBase.Network.DiagnosticsSubscription {
    init(_ subscription: SwiftFulcrum.Client.Diagnostics.Subscription) {
        self.init(methodPath: subscription.methodPath, identifier: subscription.identifier)
    }
}

extension _OpalBase.Network.LogLevel {
    init(_ level: SwiftFulcrum.Logging.Level) {
        switch level {
        case .trace: self = .trace
        case .debug: self = .debug
        case .info: self = .info
        case .notice: self = .notice
        case .warning: self = .warning
        case .error: self = .error
        case .critical: self = .critical
        }
    }
    
    var fulcrumLevel: SwiftFulcrum.Logging.Level {
        switch self {
        case .trace: return .trace
        case .debug: return .debug
        case .info: return .info
        case .notice: return .notice
        case .warning: return .warning
        case .error: return .error
        case .critical: return .critical
        }
    }
}

