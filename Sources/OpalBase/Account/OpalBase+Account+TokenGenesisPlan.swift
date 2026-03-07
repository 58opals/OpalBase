// OpalBase+Account+TokenGenesisPlan.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenGenesisPlan: Sendable {
        public struct TransactionResult: Sendable {
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let category: OpalBase.CashTokens.CategoryIDModel
            public let mintedOutputs: [OpalBase.Transaction.OutputModel]
            public let bitcoinCashChange: SpendPlan.TransactionResult.Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        category: OpalBase.CashTokens.CategoryIDModel,
                        mintedOutputs: [OpalBase.Transaction.OutputModel],
                        bitcoinCashChange: SpendPlan.TransactionResult.Change?) {
                self.transaction = transaction
                self.fee = fee
                self.category = category
                self.mintedOutputs = mintedOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let genesis: TokenGenesis
        public let category: OpalBase.CashTokens.CategoryIDModel
        public let feeRate: UInt64
        public let genesisInput: OpalBase.Transaction.OutputModel.UnspentModel
        public let bitcoinCashInputs: [OpalBase.Transaction.OutputModel.UnspentModel]
        public let outputs: [OpalBase.Transaction.OutputModel]
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: OpalBase.Account.SpendReservationModel
        private let privateKeys: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey]
        private let changeOutput: OpalBase.Transaction.OutputModel
        private let shouldAllowDustDonation: Bool
        private let shouldRandomizeRecipientOrdering: Bool
        private let plannedMintedOutputs: [OpalBase.Transaction.OutputModel]
        
        init(genesis: TokenGenesis,
             category: OpalBase.CashTokens.CategoryIDModel,
             feeRate: UInt64,
             genesisInput: OpalBase.Transaction.OutputModel.UnspentModel,
             bitcoinCashInputs: [OpalBase.Transaction.OutputModel.UnspentModel],
             outputs: [OpalBase.Transaction.OutputModel],
             reservationHandle: OpalBase.Account.SpendReservationModel,
             privateKeys: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey],
             changeOutput: OpalBase.Transaction.OutputModel,
             plannedMintedOutputs: [OpalBase.Transaction.OutputModel],
             shouldAllowDustDonation: Bool,
             shouldRandomizeRecipientOrdering: Bool) {
            self.genesis = genesis
            self.category = category
            self.feeRate = feeRate
            self.genesisInput = genesisInput
            self.bitcoinCashInputs = bitcoinCashInputs
            self.outputs = outputs
            self.reservationHandle = reservationHandle
            self.privateKeys = privateKeys
            self.changeOutput = changeOutput
            self.plannedMintedOutputs = plannedMintedOutputs
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: ECDSAModel.SignatureFormatModel = .schnorr,
                                     unlockers: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.Transaction.UnlockerModel] = .init()) throws -> TransactionResult {
            let core = try OpalBase.Account.buildTransactionCore(privateKeys: privateKeys,
                                                        recipientOutputs: outputs,
                                                        changeOutput: changeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: OpalBase.Account.Error.tokenGenesisTransactionBuildFailed)
            let resolvedMintedOutputs = OpalBase.Transaction.OutputModel.ResolverModel.resolve(plannedMintedOutputs,
                                                                            in: core.transaction.outputs)
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     category: category,
                                     mintedOutputs: resolvedMintedOutputs,
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
                mapBroadcastError: OpalBase.Account.Error.tokenGenesisBroadcastFailed
            )
        }
    }
}
