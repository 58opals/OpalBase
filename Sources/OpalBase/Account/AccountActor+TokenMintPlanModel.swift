// AccountActor+TokenMintPlanModel.swift

import Foundation

extension AccountActor {
    public struct TokenMintPlanModel: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlanModel.TransactionResult.Change
            
            public let transaction: TransactionModel
            public let fee: SatoshiModel
            public let tokenOutputs: [TransactionModel.OutputModel]
            public let bitcoinCashChange: Change?
            
            public init(transaction: TransactionModel,
                        fee: SatoshiModel,
                        tokenOutputs: [TransactionModel.OutputModel],
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenOutputs = tokenOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let mint: TokenMintModel
        public let feeRate: UInt64
        public let authorityInput: TransactionModel.OutputModel.UnspentModel
        public let extraFungibleInputs: [TransactionModel.OutputModel.UnspentModel]
        public let bitcoinCashInputs: [TransactionModel.OutputModel.UnspentModel]
        public let tokenRecipientOutputs: [TransactionModel.OutputModel]
        public let authorityReturnOutput: TransactionModel.OutputModel?
        public let fungiblePreservationOutput: TransactionModel.OutputModel?
        public let bitcoinCashChangeOutput: TransactionModel.OutputModel
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: AccountActor.SpendReservationModel
        private let privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel]
        private let plannedTokenOutputs: [TransactionModel.OutputModel]
        private let organizedTokenOutputs: [TransactionModel.OutputModel]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(mint: TokenMintModel,
             feeRate: UInt64,
             authorityInput: TransactionModel.OutputModel.UnspentModel,
             extraFungibleInputs: [TransactionModel.OutputModel.UnspentModel],
             bitcoinCashInputs: [TransactionModel.OutputModel.UnspentModel],
             tokenRecipientOutputs: [TransactionModel.OutputModel],
             authorityReturnOutput: TransactionModel.OutputModel?,
             fungiblePreservationOutput: TransactionModel.OutputModel?,
             bitcoinCashChangeOutput: TransactionModel.OutputModel,
             shouldAllowDustDonation: Bool,
             reservationHandle: AccountActor.SpendReservationModel,
             privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
             organizedTokenOutputs: [TransactionModel.OutputModel],
             shouldRandomizeRecipientOrdering: Bool) {
            self.mint = mint
            self.feeRate = feeRate
            self.authorityInput = authorityInput
            self.extraFungibleInputs = extraFungibleInputs
            self.bitcoinCashInputs = bitcoinCashInputs
            self.tokenRecipientOutputs = tokenRecipientOutputs
            self.authorityReturnOutput = authorityReturnOutput
            self.fungiblePreservationOutput = fungiblePreservationOutput
            self.bitcoinCashChangeOutput = bitcoinCashChangeOutput
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.reservationHandle = reservationHandle
            self.privateKeys = privateKeys
            self.plannedTokenOutputs = tokenRecipientOutputs
            + [authorityReturnOutput, fungiblePreservationOutput].compactMap { $0 }
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
            let resolvedTokenOutputs = TransactionModel.OutputModel.ResolverModel.resolve(plannedTokenOutputs,
                                                                           in: core.transaction.outputs)
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     tokenOutputs: resolvedTokenOutputs,
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
                mapBroadcastError: AccountActor.Error.tokenMintBroadcastFailed
            )
        }
    }
}
