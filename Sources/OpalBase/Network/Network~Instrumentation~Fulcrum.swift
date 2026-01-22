// Network~Instrumentation~Fulcrum.swift

import SwiftFulcrum

extension Network.DiagnosticsSnapshot {
    init(_ snapshot: Fulcrum.Diagnostics.Snapshot) {
        self.init(
            reconnectionAttemptCount: snapshot.reconnectAttempts,
            reconnectSuccesses: snapshot.reconnectSuccesses,
            inflightUnaryCallCount: snapshot.inflightUnaryCallCount,
            activeSubscriptionCount: snapshot.activeSubscriptionCount
        )
    }
}

extension Network.DiagnosticsSubscription {
    init(_ subscription: Fulcrum.Diagnostics.Subscription) {
        self.init(methodPath: subscription.methodPath, identifier: subscription.identifier)
    }
}

extension Network.LogLevel {
    init(_ level: Log.Level) {
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
    
    var fulcrumLevel: Log.Level {
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
