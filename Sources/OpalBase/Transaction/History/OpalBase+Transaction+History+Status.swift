// OpalBase+Transaction+History+Status.swift

import Foundation

extension _OpalBase.Transaction.History {
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

extension _OpalBase.Transaction.History.Status {
    struct Transition: Sendable, Hashable {
        let status: OpalBase.Transaction.History.Status
        private let explicitConfirmationHeight: UInt64?

        init(status: OpalBase.Transaction.History.Status, confirmationHeight: UInt64?) {
            self.status = status
            self.explicitConfirmationHeight = confirmationHeight
        }
        
        var isConfirmed: Bool { status == .confirmed }
        
        func resolveConfirmationHeight(forHeight height: Int) -> UInt64? {
            guard isConfirmed else { return nil }
            if let explicitConfirmationHeight {
                return explicitConfirmationHeight
            }
            guard height > 0 else { return nil }
            return UInt64(height)
        }
        
        var confirmationHeight: UInt64? { explicitConfirmationHeight }
    }

    static func makeTransition(forHeight height: Int,
                               from previousStatus: OpalBase.Transaction.History.Status?) -> Transition
    {
        if height > 0 {
            return Transition(status: .confirmed, confirmationHeight: UInt64(height))
        }
        
        guard let previousStatus else {
            return Transition(status: .discovered, confirmationHeight: nil)
        }
        
        switch previousStatus {
        case .confirmed, .discovered, .failed:
            return Transition(status: .pending, confirmationHeight: nil)
        case .pending:
            return Transition(status: previousStatus, confirmationHeight: nil)
        }
    }
}
