#if os(macOS)
// OpalBase+Account+CashFusionObserverSink.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    final class CashFusionObserverSink: OpalFusion.Client.StateObserver, @unchecked Sendable {
        weak var owner: OpalBase.Account.CashFusionSession?

        func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
            await owner?.receiveCashFusionSnapshot(snapshot)
        }
    }
}
#endif
