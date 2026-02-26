import Foundation
@testable import OpalBase

actor WalletFulcrumAddressMonitorEventRecorderActor {
    private var events: [WalletActor.FulcrumAddressActor.MonitorActor.Event] = .init()

    func append(_ event: WalletActor.FulcrumAddressActor.MonitorActor.Event) {
        events.append(event)
    }

    func snapshot() -> [WalletActor.FulcrumAddressActor.MonitorActor.Event] {
        events
    }
}

enum WalletFulcrumAddressMonitorSupportModel {
    private enum TimeoutError: Swift.Error {
        case timedOut(String)
    }

    static func waitForEvents(
        _ recorder: WalletFulcrumAddressMonitorEventRecorderActor,
        description: String,
        timeout: Duration = .seconds(8),
        condition: ([WalletActor.FulcrumAddressActor.MonitorActor.Event]) -> Bool
    ) async throws -> [WalletActor.FulcrumAddressActor.MonitorActor.Event] {
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

    static func hasAddressTracked(_ events: [WalletActor.FulcrumAddressActor.MonitorActor.Event]) -> Bool {
        events.contains { if case .addressTracked = $0 { true } else { false } }
    }

    static func hasUTXOChange(_ events: [WalletActor.FulcrumAddressActor.MonitorActor.Event]) -> Bool {
        events.contains { if case .utxosChanged = $0 { true } else { false } }
    }

    static func hasHistoryChange(_ events: [WalletActor.FulcrumAddressActor.MonitorActor.Event]) -> Bool {
        events.contains { if case .historyChanged = $0 { true } else { false } }
    }

    static func hasConfirmationChange(_ events: [WalletActor.FulcrumAddressActor.MonitorActor.Event]) -> Bool {
        events.contains { if case .confirmationsChanged = $0 { true } else { false } }
    }

    static func hasFullRefresh(_ events: [WalletActor.FulcrumAddressActor.MonitorActor.Event]) -> Bool {
        events.contains { if case .performedFullRefresh = $0 { true } else { false } }
    }

    static func hasFailure(
        _ events: [WalletActor.FulcrumAddressActor.MonitorActor.Event],
        address: AddressModel
    ) -> Bool {
        events.contains {
            guard case .encounteredFailure(let failure) = $0 else { return false }
            return failure.address == address
        }
    }

    static func hasTermination(
        _ events: [WalletActor.FulcrumAddressActor.MonitorActor.Event],
        reason: WalletActor.FulcrumAddressActor.MonitorActor.Termination.Reason
    ) -> Bool {
        events.contains {
            guard case .terminated(let termination) = $0 else { return false }
            return termination.reason == reason
        }
    }
}
