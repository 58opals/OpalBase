// WalletFulcrumAddressMonitorSupportModel.swift

import Foundation
@testable import OpalBase

enum WalletFulcrumAddressMonitorSupportModel {
    private enum TimeoutError: Swift.Error {
        case timedOut(String)
    }

    static func waitForEvents(
        _ recorder: WalletFulcrumAddressMonitorEventRecorderActor,
        description: String,
        timeout: Duration = .seconds(8),
        condition: ([OpalBase.Wallet.Fulcrum.Monitor.Event]) -> Bool
    ) async throws -> [OpalBase.Wallet.Fulcrum.Monitor.Event] {
        let deadline = ContinuousClock.now + timeout
        while ContinuousClock.now < deadline {
            let events = await recorder.snapshot()
            if condition(events) {
                return events
            }
            try await Task.sleep(for: .milliseconds(20))
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
