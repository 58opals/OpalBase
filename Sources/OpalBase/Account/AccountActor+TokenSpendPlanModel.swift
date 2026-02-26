// AccountActor+TokenSpendPlanModel.swift

import Foundation

extension AccountActor {
    public struct TokenSpendPlanModel: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlanModel.TransactionResult.Change
            
            public let transaction: TransactionModel
            public let fee: SatoshiModel
            public let tokenChangeOutputs: [TransactionModel.OutputModel]
            public let bitcoinCashChange: Change?
            
            public init(transaction: TransactionModel,
                        fee: SatoshiModel,
                        tokenChangeOutputs: [TransactionModel.OutputModel],
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenChangeOutputs = tokenChangeOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let transfer: TokenTransferModel
        public let feeRate: UInt64
        public let tokenInputs: [TransactionModel.OutputModel.UnspentModel]
        public let bitcoinCashInputs: [TransactionModel.OutputModel.UnspentModel]
        public let tokenRecipientOutputs: [TransactionModel.OutputModel]
        public let tokenChangeOutputs: [TransactionModel.OutputModel]
        public let bitcoinCashChangeOutput: TransactionModel.OutputModel
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: AccountActor.SpendReservationModel
        private let privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel]
        private let organizedTokenOutputs: [TransactionModel.OutputModel]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(transfer: TokenTransferModel,
             feeRate: UInt64,
             tokenInputs: [TransactionModel.OutputModel.UnspentModel],
             bitcoinCashInputs: [TransactionModel.OutputModel.UnspentModel],
             tokenRecipientOutputs: [TransactionModel.OutputModel],
             tokenChangeOutputs: [TransactionModel.OutputModel],
             bitcoinCashChangeOutput: TransactionModel.OutputModel,
             shouldAllowDustDonation: Bool,
             reservationHandle: AccountActor.SpendReservationModel,
             privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
             organizedTokenOutputs: [TransactionModel.OutputModel],
             shouldRandomizeRecipientOrdering: Bool) {
            self.transfer = transfer
            self.feeRate = feeRate
            self.tokenInputs = tokenInputs
            self.bitcoinCashInputs = bitcoinCashInputs
            self.tokenRecipientOutputs = tokenRecipientOutputs
            self.tokenChangeOutputs = tokenChangeOutputs
            self.bitcoinCashChangeOutput = bitcoinCashChangeOutput
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.reservationHandle = reservationHandle
            self.privateKeys = privateKeys
            self.organizedTokenOutputs = organizedTokenOutputs
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: ECDSAModel.SignatureFormatModel = .schnorr,
                                     unlockers: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel] = .init()) throws -> TransactionResult {
            let core = try AccountActor.buildTransactionCore(privateKeys: privateKeys,
                                                        recipientOutputs: organizedTokenOutputs,
                                                        changeOutput: bitcoinCashChangeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: AccountActor.Error.transactionBuildFailed)
            let resolvedTokenChangeOutputs = TransactionModel.OutputModel.ResolverModel.resolve(tokenChangeOutputs,
                                                                                 in: core.transaction.outputs)
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     tokenChangeOutputs: resolvedTokenChangeOutputs,
                                     bitcoinCashChange: core.bitcoinCashChange)
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
