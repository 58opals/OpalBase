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
