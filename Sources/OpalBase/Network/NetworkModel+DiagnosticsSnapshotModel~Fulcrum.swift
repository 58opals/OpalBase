// NetworkModel~Instrumentation~FulcrumClient.swift

import SwiftFulcrum

extension NetworkModel.DiagnosticsSnapshotModel {
    init(_ snapshot: SwiftFulcrum.FulcrumClient.DiagnosticsModel.SnapshotModel) {
        self.init(
            reconnectionAttemptCount: snapshot.reconnectAttempts,
            reconnectSuccesses: snapshot.reconnectSuccesses,
            inflightUnaryCallCount: snapshot.inflightUnaryCallCount,
            activeSubscriptionCount: snapshot.activeSubscriptionCount
        )
    }
}

extension NetworkModel.DiagnosticsSubscriptionModel {
    init(_ subscription: SwiftFulcrum.FulcrumClient.DiagnosticsModel.SubscriptionModel) {
        self.init(methodPath: subscription.methodPath, identifier: subscription.identifier)
    }
}

extension NetworkModel.LogLevelModel {
    init(_ level: LogModel.LevelModel) {
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
    
    var fulcrumLevel: LogModel.LevelModel {
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
