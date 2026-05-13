// OpalBase+Account+CashFusionObserverSink.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    actor CashFusionObserverSink: OpalFusion.Client.StateObserver {
        private weak var owner: OpalBase.Account.CashFusionSession?

        func bind(to owner: OpalBase.Account.CashFusionSession) {
            self.owner = owner
        }

        func unbind() {
            owner = nil
        }

        func receive(_ snapshot: OpalFusion.Client.Session.Snapshot) async {
            guard let owner else {
                return
            }

            await owner.receiveCashFusionSnapshot(snapshot)
        }
    }
}
#endif
