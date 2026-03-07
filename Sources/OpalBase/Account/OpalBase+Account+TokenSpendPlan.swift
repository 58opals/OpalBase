// OpalBase.Account+TokenSpendPlan.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenSpendPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let tokenChangeOutputs: [OpalBase.Transaction.OutputModel]
            public let bitcoinCashChange: Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        tokenChangeOutputs: [OpalBase.Transaction.OutputModel],
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenChangeOutputs = tokenChangeOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let transfer: TokenTransfer
        public let feeRate: UInt64
        public let tokenInputs: [OpalBase.Transaction.OutputModel.UnspentModel]
        public let bitcoinCashInputs: [OpalBase.Transaction.OutputModel.UnspentModel]
        public let tokenRecipientOutputs: [OpalBase.Transaction.OutputModel]
        public let tokenChangeOutputs: [OpalBase.Transaction.OutputModel]
        public let bitcoinCashChangeOutput: OpalBase.Transaction.OutputModel
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: OpalBase.Account.SpendReservationModel
        private let privateKeys: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey]
        private let organizedTokenOutputs: [OpalBase.Transaction.OutputModel]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(transfer: TokenTransfer,
             feeRate: UInt64,
             tokenInputs: [OpalBase.Transaction.OutputModel.UnspentModel],
             bitcoinCashInputs: [OpalBase.Transaction.OutputModel.UnspentModel],
             tokenRecipientOutputs: [OpalBase.Transaction.OutputModel],
             tokenChangeOutputs: [OpalBase.Transaction.OutputModel],
             bitcoinCashChangeOutput: OpalBase.Transaction.OutputModel,
             shouldAllowDustDonation: Bool,
             reservationHandle: OpalBase.Account.SpendReservationModel,
             privateKeys: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey],
             organizedTokenOutputs: [OpalBase.Transaction.OutputModel],
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
                                     unlockers: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.Transaction.UnlockerModel] = .init()) throws -> TransactionResult {
            let core = try OpalBase.Account.buildTransactionCore(privateKeys: privateKeys,
                                                        recipientOutputs: organizedTokenOutputs,
                                                        changeOutput: bitcoinCashChangeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: OpalBase.Account.Error.transactionBuildFailed)
            let resolvedTokenChangeOutputs = OpalBase.Transaction.OutputModel.ResolverModel.resolve(tokenChangeOutputs,
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
        
        public func buildAndBroadcast(via handler: OpalBase.Network.TransactionHandling,
                                      signatureFormat: ECDSAModel.SignatureFormatModel = .schnorr,
                                      unlockers: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.Transaction.UnlockerModel] = .init()) async throws -> (hash: OpalBase.Transaction.HashModel, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: OpalBase.Account.Error.broadcastFailed
            )
        }
    }
}
