// OpalBase+Account+CashFusionObserverSink.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    final class CashFusionObserverSink: OpalFusion.Host.EventObserver, OpalFusion.Client.StateObserver, @unchecked Sendable {
        weak var owner: OpalBase.Account.CashFusionSession?

        private let eventObserver: (any OpalFusion.Host.EventObserver)?
        private let stateObserver: (any OpalFusion.Client.StateObserver)?

        init(
            eventObserver: (any OpalFusion.Host.EventObserver)?,
            stateObserver: (any OpalFusion.Client.StateObserver)?
        ) {
            self.eventObserver = eventObserver
            self.stateObserver = stateObserver
        }

        func receive(
            _ event: OpalFusion.Host.Event,
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async {
            await eventObserver?.receive(event, for: roundIdentifier)
        }

        func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
            await stateObserver?.receive(snapshot)
            await owner?.receiveCashFusionSnapshot(snapshot)
        }
    }
}
