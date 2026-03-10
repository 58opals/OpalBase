// OpalBase+Network+DiagnosticsSnapshot.swift

import Foundation

extension _OpalBase.Network {
    public struct DiagnosticsSnapshot: Sendable, Equatable {
        public let reconnectionAttemptCount: Int
        public let reconnectSuccesses: Int
        public let inflightUnaryCallCount: Int
        public let activeSubscriptionCount: Int
        
        public init(
            reconnectionAttemptCount: Int,
            reconnectSuccesses: Int,
            inflightUnaryCallCount: Int,
            activeSubscriptionCount: Int
        ) {
            self.reconnectionAttemptCount = reconnectionAttemptCount
            self.reconnectSuccesses = reconnectSuccesses
            self.inflightUnaryCallCount = inflightUnaryCallCount
            self.activeSubscriptionCount = activeSubscriptionCount
        }
    }
}
