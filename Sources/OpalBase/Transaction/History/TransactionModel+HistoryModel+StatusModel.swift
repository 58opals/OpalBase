// TransactionModel+HistoryModel+StatusModel.swift

import Foundation

extension TransactionModel.HistoryModel {
    public enum StatusModel: String, Sendable, Hashable, Codable {
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

extension TransactionModel.HistoryModel.StatusModel {
    struct TransitionModel: Sendable, Hashable {
        let status: TransactionModel.HistoryModel.StatusModel
        private let explicitConfirmationHeight: UInt64?
        
        init(status: TransactionModel.HistoryModel.StatusModel, confirmationHeight: UInt64?) {
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
                               from previousStatus: TransactionModel.HistoryModel.StatusModel?) -> TransitionModel
    {
        if height > 0 {
            return TransitionModel(status: .confirmed, confirmationHeight: UInt64(height))
        }
        
        guard let previousStatus else {
            return TransitionModel(status: .discovered, confirmationHeight: nil)
        }
        
        switch previousStatus {
        case .confirmed, .discovered:
            return TransitionModel(status: .pending, confirmationHeight: nil)
        case .pending, .failed:
            return TransitionModel(status: previousStatus, confirmationHeight: nil)
        }
    }
}
