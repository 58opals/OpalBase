// AccountActor+TokenGenesisPlanModel.swift

import Foundation
import OpalCrypto

extension AccountActor {
    public struct TokenGenesisPlanModel: Sendable {
        public struct TransactionResult: Sendable {
            public let transaction: TransactionModel
            public let fee: SatoshiModel
            public let category: CashTokensModel.CategoryIDModel
            public let mintedOutputs: [TransactionModel.OutputModel]
            public let bitcoinCashChange: SpendPlanModel.TransactionResult.Change?
            
            public init(transaction: TransactionModel,
                        fee: SatoshiModel,
                        category: CashTokensModel.CategoryIDModel,
                        mintedOutputs: [TransactionModel.OutputModel],
                        bitcoinCashChange: SpendPlanModel.TransactionResult.Change?) {
                self.transaction = transaction
                self.fee = fee
                self.category = category
                self.mintedOutputs = mintedOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let genesis: TokenGenesisModel
        public let category: CashTokensModel.CategoryIDModel
        public let feeRate: UInt64
        public let genesisInput: TransactionModel.OutputModel.UnspentModel
        public let bitcoinCashInputs: [TransactionModel.OutputModel.UnspentModel]
        public let outputs: [TransactionModel.OutputModel]
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: AccountActor.SpendReservationModel
        private let privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel]
        private let changeOutput: TransactionModel.OutputModel
        private let shouldAllowDustDonation: Bool
        private let shouldRandomizeRecipientOrdering: Bool
        private let plannedMintedOutputs: [TransactionModel.OutputModel]
        
        init(genesis: TokenGenesisModel,
             category: CashTokensModel.CategoryIDModel,
             feeRate: UInt64,
             genesisInput: TransactionModel.OutputModel.UnspentModel,
             bitcoinCashInputs: [TransactionModel.OutputModel.UnspentModel],
             outputs: [TransactionModel.OutputModel],
             reservationHandle: AccountActor.SpendReservationModel,
             privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
             changeOutput: TransactionModel.OutputModel,
             plannedMintedOutputs: [TransactionModel.OutputModel],
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
        
        public func buildTransaction(signatureFormat: EllipticCurveDigitalSignatureAlgorithmModel.SignatureFormatModel = .schnorr,
                                     unlockers: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel] = .init()) throws -> TransactionResult {
            let core = try AccountActor.buildTransactionCore(privateKeys: privateKeys,
                                                        recipientOutputs: outputs,
                                                        changeOutput: changeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: AccountActor.Error.tokenGenesisTransactionBuildFailed)
            let resolvedMintedOutputs = TransactionModel.OutputModel.ResolverModel.resolve(plannedMintedOutputs,
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
        
        public func buildAndBroadcast(via handler: NetworkModel.TransactionHandling,
                                      signatureFormat: EllipticCurveDigitalSignatureAlgorithmModel.SignatureFormatModel = .schnorr,
                                      unlockers: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel] = .init()) async throws -> (hash: TransactionModel.HashModel, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: AccountActor.Error.tokenGenesisBroadcastFailed
            )
        }
    }
}
