// OpalBase+WalletUnsignedSpendPlan.swift

import Foundation

public extension OpalBase {
    /// Reserved spend plan for external review and signing without retained private-key material.
    struct WalletUnsignedSpendPlan: Sendable {
        public let payment: OpalBase.Account.Payment
        public let feeRate: UInt64
        public let inputs: [OpalBase.Transaction.Output.Unspent]
        public let totalSelectedAmount: OpalBase.Satoshi
        public let targetAmount: OpalBase.Satoshi
        public let envelope: OpalBase.WalletUnsignedTransactionEnvelope
        public var reservationDate: Date { reservationHandle.reservationDate }

        private let reservationHandle: OpalBase.Account.SpendReservation

        init(
            payment: OpalBase.Account.Payment,
            feeRate: UInt64,
            inputs: [OpalBase.Transaction.Output.Unspent],
            totalSelectedAmount: OpalBase.Satoshi,
            targetAmount: OpalBase.Satoshi,
            envelope: OpalBase.WalletUnsignedTransactionEnvelope,
            reservationHandle: OpalBase.Account.SpendReservation
        ) {
            self.payment = payment
            self.feeRate = feeRate
            self.inputs = inputs
            self.totalSelectedAmount = totalSelectedAmount
            self.targetAmount = targetAmount
            self.envelope = envelope
            self.reservationHandle = reservationHandle
        }

        public func completeExternalSigning(
            with signedTransaction: OpalBase.Transaction
        ) async throws -> OpalBase.Transaction {
            try envelope.validateSignedTransactionStructure(signedTransaction)
            try await reservationHandle.complete()
            return signedTransaction
        }

        public func cancelReservation() async throws {
            try await reservationHandle.cancel()
        }
    }
}
