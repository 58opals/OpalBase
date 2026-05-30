// OpalBase+Network+TransactionConfirmationStatus.swift

import Foundation

extension _OpalBase.Network {
    public struct TransactionConfirmationStatus: Sendable, Equatable {
        public let transactionHash: OpalBase.Transaction.Hash
        public let transactionHeight: Int?
        public let tipHeight: UInt64
        public let confirmations: UInt?
        
        public init(transactionHash: OpalBase.Transaction.Hash,
                    transactionHeight: Int?,
                    tipHeight: UInt64,
                    confirmations: UInt?) {
            self.transactionHash = transactionHash
            self.transactionHeight = transactionHeight
            self.tipHeight = tipHeight
            self.confirmations = confirmations
        }
    }
}

extension _OpalBase.Network.TransactionConfirmationStatus {
    func validateConsistency() throws {
        guard let transactionHeight else {
            if let confirmations, confirmations > 0 {
                throw Self.protocolViolation("Confirmation count requires a confirmed transaction height")
            }
            return
        }

        guard transactionHeight > 0 else {
            throw Self.protocolViolation("Confirmation status height must be positive")
        }

        guard UInt64(transactionHeight) <= tipHeight else {
            throw Self.protocolViolation("Confirmation status height exceeds tip height")
        }
        guard let confirmations else {
            throw Self.protocolViolation("Confirmed transaction height requires confirmation count")
        }
        let expectedConfirmations = tipHeight - UInt64(transactionHeight) + 1
        guard UInt64(confirmations) == expectedConfirmations else {
            throw Self.protocolViolation("Confirmation status count does not match height and tip")
        }
    }

    private static func protocolViolation(_ message: String) -> OpalBase.Network.Error {
        OpalBase.Network.Error(reason: .protocolViolation, message: message)
    }
}
