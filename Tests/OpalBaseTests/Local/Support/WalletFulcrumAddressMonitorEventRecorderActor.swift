// WalletFulcrumAddressMonitorEventRecorderActor.swift

import Foundation
@testable import OpalBase

actor WalletFulcrumAddressMonitorEventRecorderActor {
    private var events: [OpalBase.Wallet.Fulcrum.Monitor.Event] = .init()

    func append(_ event: OpalBase.Wallet.Fulcrum.Monitor.Event) {
        events.append(event)
    }

    func snapshot() -> [OpalBase.Wallet.Fulcrum.Monitor.Event] {
        events
    }
}
