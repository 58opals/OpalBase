// BlockHeaderReaderTestActor.swift

import Foundation
@testable import OpalBase

actor BlockHeaderReaderTestActor: OpalBase.Network.BlockHeaderReadable {
    private let snapshots: [OpalBase.Network.BlockHeaderSnapshot]
    private let subscriptionError: Swift.Error?
    private let shouldKeepSubscriptionOpen: Bool

    init(
        snapshots: [OpalBase.Network.BlockHeaderSnapshot],
        subscriptionError: Swift.Error? = nil,
        shouldKeepSubscriptionOpen: Bool = true
    ) {
        self.snapshots = snapshots
        self.subscriptionError = subscriptionError
        self.shouldKeepSubscriptionOpen = shouldKeepSubscriptionOpen
    }

    func fetchTip() async throws -> OpalBase.Network.BlockHeaderSnapshot {
        snapshots.first ?? .init(height: 0, headerHexadecimal: String(repeating: "0", count: 160))
    }

    func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error> {
        let snapshots = self.snapshots
        let subscriptionError = self.subscriptionError
        return AsyncThrowingStream { continuation in
            for snapshot in snapshots {
                continuation.yield(snapshot)
            }
            if let subscriptionError {
                continuation.finish(throwing: subscriptionError)
                return
            }
            if !shouldKeepSubscriptionOpen {
                continuation.finish()
            }
        }
    }
}
