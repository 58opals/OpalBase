// OpalBase+Block+HeaderModel+ChainActor+CheckpointModel.swift

import Foundation

extension _OpalBase.Block.HeaderModel.ChainActor {
    struct CheckpointModel: Equatable, Sendable {
        public let height: UInt32
        public let hash: Data
        
        public init(height: UInt32, hash: Data) {
            self.height = height
            self.hash = hash
        }
    }
    
    struct TipStatusModel: Equatable, Sendable {
        enum Condition: Equatable, Sendable {
            case fresh
            case stale(by: TimeInterval)
            case future(by: TimeInterval)
        }
        
        public let condition: Condition
        public let headerTime: Date
        public let assessedAt: Date
        public let height: UInt32
        
        public init(condition: Condition, headerTime: Date, assessedAt: Date, height: UInt32) {
            self.condition = condition
            self.headerTime = headerTime
            self.assessedAt = assessedAt
            self.height = height
        }
        
        public var drift: TimeInterval {
            assessedAt.timeIntervalSince(headerTime)
        }
    }
    
    enum MaintenanceEventModel: Equatable, Sendable {
        case requiresResynchronization(from: CheckpointModel)
        case staleTip(status: TipStatusModel)
    }
}

extension _OpalBase.Block.HeaderModel.ChainActor.CheckpointModel {
    static var defaultCheckpoint: OpalBase.Block.HeaderModel.ChainActor.CheckpointModel {
        let hashHexadecimalString = "000000000019d6689c085ae165831e934ff763ae46a2a6c172b3f1b60a8ce26f"
        let hash = (try? Data(hexadecimalString: hashHexadecimalString))?.reversedData ?? Data(repeating: 0, count: 32)
        return .init(height: 0, hash: hash)
    }
}
