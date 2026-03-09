// WalletFulcrumAddressMonitorEventRecorderActor.swift

import Foundation
@testable import OpalBase

actor WalletFulcrumAddressMonitorEventRecorderActor {
    private var events: [OpalBase.Wallet.Fulcrum.Monitor.Event] = .init()
    private var snapshotContinuations: [UUID: AsyncStream<[OpalBase.Wallet.Fulcrum.Monitor.Event]>.Continuation] = .init()

    func append(_ event: OpalBase.Wallet.Fulcrum.Monitor.Event) {
        events.append(event)
        for continuation in snapshotContinuations.values {
            continuation.yield(events)
        }
    }

    func snapshot() -> [OpalBase.Wallet.Fulcrum.Monitor.Event] {
        events
    }

    func makeSnapshotStream() -> AsyncStream<[OpalBase.Wallet.Fulcrum.Monitor.Event]> {
        AsyncStream { continuation in
            let identifier = UUID()
            snapshotContinuations[identifier] = continuation
            continuation.yield(events)
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeSnapshotContinuation(withIdentifier: identifier) }
            }
        }
    }

    private func removeSnapshotContinuation(withIdentifier identifier: UUID) {
        snapshotContinuations.removeValue(forKey: identifier)
    }
}
