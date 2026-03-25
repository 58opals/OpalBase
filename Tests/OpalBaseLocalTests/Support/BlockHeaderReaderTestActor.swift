// BlockHeaderReaderTestActor.swift

import Foundation
@testable import OpalBase

actor BlockHeaderReaderTestActor: OpalBase.Network.BlockHeaderReadable {
    private let snapshots: [OpalBase.Network.BlockHeaderSnapshot]
    private let subscriptionError: Swift.Error?
    private let shouldKeepSubscriptionOpen: Bool
    private var subscriptionCount: Int = 0
    private var terminationCount: Int = 0

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
        subscriptionCount += 1
        let snapshots = self.snapshots
        let subscriptionError = self.subscriptionError
        return AsyncThrowingStream { continuation in
            continuation.onTermination = { [weak self] _ in
                Task { await self?.recordTermination() }
            }
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

    func readSubscriptionCount() -> Int {
        subscriptionCount
    }

    func readTerminationCount() -> Int {
        terminationCount
    }

    private func recordTermination() {
        terminationCount += 1
    }
}
