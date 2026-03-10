// OpalBase+Block+Header+ChainActor+MaintenanceEvent.swift

import Foundation

extension _OpalBase.Block.Header.ChainActor {
    enum MaintenanceEvent: Equatable, Sendable {
        case requiresResynchronization(from: Checkpoint)
        case staleTip(status: TipStatus)
    }
}
