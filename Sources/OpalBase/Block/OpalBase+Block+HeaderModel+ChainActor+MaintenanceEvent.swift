// OpalBase+Block+HeaderModel+ChainActor+MaintenanceEvent.swift

import Foundation

extension _OpalBase.Block.HeaderModel.ChainActor {
    enum MaintenanceEvent: Equatable, Sendable {
        case requiresResynchronization(from: Checkpoint)
        case staleTip(status: TipStatus)
    }
}
