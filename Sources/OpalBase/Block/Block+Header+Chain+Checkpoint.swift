// Block+Header+Chain+Checkpoint.swift

import Foundation

extension Block.Header.Chain {
    struct Checkpoint: Equatable, Sendable {
        public let height: UInt32
        public let hash: Data
        
        public init(height: UInt32, hash: Data) {
            self.height = height
            self.hash = hash
        }
    }
    
    struct TipStatus: Equatable, Sendable {
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
    
    enum MaintenanceEvent: Equatable, Sendable {
        case requiresResynchronization(from: Checkpoint)
        case staleTip(status: TipStatus)
    }
}
