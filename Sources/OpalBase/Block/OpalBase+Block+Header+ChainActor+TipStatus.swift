// OpalBase+Block+Header+ChainActor+TipStatus.swift

import Foundation

extension _OpalBase.Block.Header.ChainActor {
    struct TipStatus: Equatable, Sendable {
        enum Condition: Equatable, Sendable {
            case fresh
            case stale(by: TimeInterval)
            case future(by: TimeInterval)

            enum Category: Equatable, Sendable {
                case fresh
                case stale
                case future
            }

            var category: Category {
                switch self {
                case .fresh:
                    return .fresh
                case .stale:
                    return .stale
                case .future:
                    return .future
                }
            }
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
}
