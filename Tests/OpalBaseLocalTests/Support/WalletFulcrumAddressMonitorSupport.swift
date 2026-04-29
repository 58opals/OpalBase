// WalletFulcrumAddressMonitorSupport.swift

import Foundation
@testable import OpalBase

enum WalletFulcrumAddressMonitorSupport {
    private enum TimeoutError: Swift.Error, Sendable {
        case timedOut(String)
    }

    static func waitForEvents(
        _ recorder: WalletFulcrumAddressMonitorEventRecorderActor,
        description: String,
        timeout: Duration = .seconds(20),
        condition: @Sendable @escaping ([OpalBase.Wallet.Fulcrum.Monitor.Event]) -> Bool
    ) async throws -> [OpalBase.Wallet.Fulcrum.Monitor.Event] {
        try await withThrowingTaskGroup(of: [OpalBase.Wallet.Fulcrum.Monitor.Event].self) { group in
            group.addTask {
                let snapshot = await recorder.snapshot()
                if condition(snapshot) {
                    return snapshot
                }

                let stream = await recorder.makeSnapshotStream()
                for await events in stream {
                    if condition(events) {
                        return events
                    }
                }

                throw TimeoutError.timedOut(description)
            }

            group.addTask {
                try await Task.sleep(for: timeout)
                throw TimeoutError.timedOut(description)
            }

            let events = try await group.next() ?? .init()
            group.cancelAll()
            return events
        }
    }

    static func waitUntil(
        description: String,
        timeout: Duration = .seconds(5),
        pollInterval: Duration = .milliseconds(10),
        condition: @Sendable @escaping () async -> Bool
    ) async throws {
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while ContinuousClock.now < deadline {
            if await condition() {
                return
            }
            try await Task.sleep(for: pollInterval)
        }

        throw TimeoutError.timedOut(description)
    }

    static func hasAddressTracked(_ events: [OpalBase.Wallet.Fulcrum.Monitor.Event]) -> Bool {
        events.contains { if case .addressTracked = $0 { true } else { false } }
    }

    static func hasUTXOChange(_ events: [OpalBase.Wallet.Fulcrum.Monitor.Event]) -> Bool {
        events.contains { if case .utxosChanged = $0 { true } else { false } }
    }

    static func hasHistoryChange(_ events: [OpalBase.Wallet.Fulcrum.Monitor.Event]) -> Bool {
        events.contains { if case .historyChanged = $0 { true } else { false } }
    }

    static func firstUTXOChangeIndex(_ events: [OpalBase.Wallet.Fulcrum.Monitor.Event]) -> Int? {
        events.firstIndex { if case .utxosChanged = $0 { true } else { false } }
    }

    static func firstUTXOChangeIndex(
        _ events: [OpalBase.Wallet.Fulcrum.Monitor.Event],
        containing utxo: OpalBase.Transaction.Output.Unspent
    ) -> Int? {
        events.firstIndex {
            guard case .utxosChanged(let changeSet) = $0 else { return false }
            return changeSet.updated.contains(utxo)
        }
    }

    static func firstHistoryChangeIndex(
        _ events: [OpalBase.Wallet.Fulcrum.Monitor.Event],
        containing transactionHash: OpalBase.Transaction.Hash
    ) -> Int? {
        events.firstIndex {
            guard case .historyChanged(let changeSet) = $0 else { return false }
            let records = changeSet.inserted + changeSet.updated
            return records.contains { $0.transactionHash == transactionHash }
        }
    }

    static func hasConfirmationChange(_ events: [OpalBase.Wallet.Fulcrum.Monitor.Event]) -> Bool {
        events.contains { if case .confirmationsChanged = $0 { true } else { false } }
    }

    static func hasFullRefresh(_ events: [OpalBase.Wallet.Fulcrum.Monitor.Event]) -> Bool {
        events.contains { if case .performedFullRefresh = $0 { true } else { false } }
    }

    static func hasFailure(
        _ events: [OpalBase.Wallet.Fulcrum.Monitor.Event],
        address: OpalBase.Address
    ) -> Bool {
        events.contains {
            guard case .encounteredFailure(let failure) = $0 else { return false }
            return failure.address == address
        }
    }

    static func hasTermination(
        _ events: [OpalBase.Wallet.Fulcrum.Monitor.Event],
        reason: OpalBase.Wallet.Fulcrum.Monitor.Termination.Reason
    ) -> Bool {
        events.contains {
            guard case .terminated(let termination) = $0 else { return false }
            return termination.reason == reason
        }
    }
}
