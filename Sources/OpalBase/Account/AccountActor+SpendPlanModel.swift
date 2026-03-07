// AccountActor+SpendPlanModel.swift

import Foundation

extension AccountActor {
    public struct SpendPlanModel: Sendable {
        public struct TransactionResult: Sendable {
            public struct Change: Sendable {
                public let entry: AddressModel.BookActor.EntryModel
                public let amount: SatoshiModel
                
                public init(entry: AddressModel.BookActor.EntryModel, amount: SatoshiModel) {
                    self.entry = entry
                    self.amount = amount
                }
            }
            
            public let transaction: TransactionModel
            public let fee: SatoshiModel
            public let change: Change?
            
            public init(transaction: TransactionModel, fee: SatoshiModel, change: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.change = change
            }
        }
        
        public let payment: PaymentModel
        public let feeRate: UInt64
        public let inputs: [TransactionModel.OutputModel.UnspentModel]
        public let totalSelectedAmount: SatoshiModel
        public let targetAmount: SatoshiModel
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        fileprivate let reservationHandle: AccountActor.SpendReservationModel
        fileprivate let changeOutput: TransactionModel.OutputModel
        fileprivate let recipientOutputs: [TransactionModel.OutputModel]
        fileprivate let privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel]
        fileprivate let shouldRandomizeRecipientOrdering: Bool
        
        init(payment: PaymentModel,
             feeRate: UInt64,
             inputs: [TransactionModel.OutputModel.UnspentModel],
             totalSelectedAmount: SatoshiModel,
             targetAmount: SatoshiModel,
             shouldAllowDustDonation: Bool,
             reservationHandle: AccountActor.SpendReservationModel,
             changeOutput: TransactionModel.OutputModel,
             recipientOutputs: [TransactionModel.OutputModel],
             privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
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
        
        public func buildTransaction(signatureFormat: ECDSAModel.SignatureFormatModel = .schnorr,
                                     unlockers: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel] = .init()) throws -> TransactionResult {
            let core = try AccountActor.buildTransactionCore(privateKeys: privateKeys,
                                                        recipientOutputs: recipientOutputs,
                                                        changeOutput: changeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: AccountActor.Error.transactionBuildFailed)
            return TransactionResult(transaction: core.transaction, fee: core.fee, change: core.bitcoinCashChange)
        }
        
        public func completeReservation() async throws {
            try await reservationHandle.complete()
        }
        
        public func cancelReservation() async throws {
            try await reservationHandle.cancel()
        }
        
        public func buildAndBroadcast(via handler: NetworkModel.TransactionHandling,
                                      signatureFormat: ECDSAModel.SignatureFormatModel = .schnorr,
                                      unlockers: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel] = .init()) async throws -> (hash: TransactionModel.HashModel, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: AccountActor.Error.broadcastFailed
            )
        }
    }
}
