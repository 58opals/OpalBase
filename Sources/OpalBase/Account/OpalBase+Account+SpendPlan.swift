// OpalBase+Account+SpendPlan.swift

import Foundation

extension _OpalBase.Account {
    public struct SpendPlan: Sendable {
        public struct TransactionResult: Sendable {
            public struct Change: Sendable {
                public let entry: OpalBase.Address.Book.EntryModel
                public let amount: OpalBase.Satoshi
                
                public init(entry: OpalBase.Address.Book.EntryModel, amount: OpalBase.Satoshi) {
                    self.entry = entry
                    self.amount = amount
                }
            }
            
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let change: Change?
            
            public init(transaction: OpalBase.Transaction, fee: OpalBase.Satoshi, change: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.change = change
            }
        }
        
        public let payment: Payment
        public let feeRate: UInt64
        public let inputs: [OpalBase.Transaction.OutputModel.Unspent]
        public let totalSelectedAmount: OpalBase.Satoshi
        public let targetAmount: OpalBase.Satoshi
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        fileprivate let reservationHandle: OpalBase.Account.SpendReservationModel
        fileprivate let changeOutput: OpalBase.Transaction.OutputModel
        fileprivate let recipientOutputs: [OpalBase.Transaction.OutputModel]
        fileprivate let privateKeys: [OpalBase.Transaction.OutputModel.Unspent: OpalBase.PrivateKey]
        fileprivate let shouldRandomizeRecipientOrdering: Bool
        
        init(payment: Payment,
             feeRate: UInt64,
             inputs: [OpalBase.Transaction.OutputModel.Unspent],
             totalSelectedAmount: OpalBase.Satoshi,
             targetAmount: OpalBase.Satoshi,
             shouldAllowDustDonation: Bool,
             reservationHandle: OpalBase.Account.SpendReservationModel,
             changeOutput: OpalBase.Transaction.OutputModel,
             recipientOutputs: [OpalBase.Transaction.OutputModel],
             privateKeys: [OpalBase.Transaction.OutputModel.Unspent: OpalBase.PrivateKey],
             shouldRandomizeRecipientOrdering: Bool) {
            self.payment = payment
            self.feeRate = feeRate
            self.inputs = inputs
            self.totalSelectedAmount = totalSelectedAmount
            self.targetAmount = targetAmount
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.reservationHandle = reservationHandle
            self.changeOutput = changeOutput
            self.recipientOutputs = recipientOutputs
            self.privateKeys = privateKeys
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: ECDSAModel.SignatureFormat = .schnorr,
                                     unlockers: [OpalBase.Transaction.OutputModel.Unspent: OpalBase.Transaction.UnlockerModel] = .init()) throws -> TransactionResult {
            let core = try OpalBase.Account.buildTransactionCore(privateKeys: privateKeys,
                                                        recipientOutputs: recipientOutputs,
                                                        changeOutput: changeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: OpalBase.Account.Error.transactionBuildFailed)
            return TransactionResult(transaction: core.transaction, fee: core.fee, change: core.bitcoinCashChange)
        }
        
        public func completeReservation() async throws {
            try await reservationHandle.complete()
        }
        
        public func cancelReservation() async throws {
            try await reservationHandle.cancel()
        }
        
        public func buildAndBroadcast(via handler: OpalBase.Network.TransactionHandling,
                                      signatureFormat: ECDSAModel.SignatureFormat = .schnorr,
                                      unlockers: [OpalBase.Transaction.OutputModel.Unspent: OpalBase.Transaction.UnlockerModel] = .init()) async throws -> (hash: OpalBase.Transaction.HashModel, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: OpalBase.Account.Error.broadcastFailed
            )
        }
    }
}
