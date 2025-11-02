// Transaction+History+Status.swift

import Foundation

extension Transaction.History {
    public enum Status: String, Sendable, Hashable, Codable {
        case discovered
        case pending
        case confirmed
        case failed
        
        public enum Verification: String, Sendable, Hashable, Codable {
            case unknown
            case pending
            case verified
            case conflicting
        }
    }
}

extension Transaction.History.Status {
    static func resolve(forHeight height: Int,
                        previousStatus: Transaction.History.Status?)
    -> (status: Transaction.History.Status, confirmationHeight: UInt64?)
    {
        if height > 0 {
            return (.confirmed, UInt64(height))
        }
        
        guard let previousStatus else {
            return (.discovered, nil)
        }
        
        switch previousStatus {
        case .confirmed:
            return (.pending, nil)
        case .discovered:
            return (.pending, nil)
        case .pending, .failed:
            return (previousStatus, nil)
        }
    }
}
