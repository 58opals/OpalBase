// OpalBase.Account+TokenMintPlan.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenMintPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let tokenOutputs: [OpalBase.Transaction.OutputModel]
            public let bitcoinCashChange: Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        tokenOutputs: [OpalBase.Transaction.OutputModel],
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenOutputs = tokenOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let mint: TokenMint
        public let feeRate: UInt64
        public let authorityInput: OpalBase.Transaction.OutputModel.UnspentModel
        public let extraFungibleInputs: [OpalBase.Transaction.OutputModel.UnspentModel]
        public let bitcoinCashInputs: [OpalBase.Transaction.OutputModel.UnspentModel]
        public let tokenRecipientOutputs: [OpalBase.Transaction.OutputModel]
        public let authorityReturnOutput: OpalBase.Transaction.OutputModel?
        public let fungiblePreservationOutput: OpalBase.Transaction.OutputModel?
        public let bitcoinCashChangeOutput: OpalBase.Transaction.OutputModel
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: OpalBase.Account.SpendReservationModel
        private let privateKeys: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey]
        private let plannedTokenOutputs: [OpalBase.Transaction.OutputModel]
        private let organizedTokenOutputs: [OpalBase.Transaction.OutputModel]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(mint: TokenMint,
             feeRate: UInt64,
             authorityInput: OpalBase.Transaction.OutputModel.UnspentModel,
             extraFungibleInputs: [OpalBase.Transaction.OutputModel.UnspentModel],
             bitcoinCashInputs: [OpalBase.Transaction.OutputModel.UnspentModel],
             tokenRecipientOutputs: [OpalBase.Transaction.OutputModel],
             authorityReturnOutput: OpalBase.Transaction.OutputModel?,
             fungiblePreservationOutput: OpalBase.Transaction.OutputModel?,
             bitcoinCashChangeOutput: OpalBase.Transaction.OutputModel,
             shouldAllowDustDonation: Bool,
             reservationHandle: OpalBase.Account.SpendReservationModel,
             privateKeys: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey],
             organizedTokenOutputs: [OpalBase.Transaction.OutputModel],
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
            let resolvedTokenOutputs = OpalBase.Transaction.OutputModel.ResolverModel.resolve(plannedTokenOutputs,
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
        
        public func buildAndBroadcast(via handler: OpalBase.Network.TransactionHandling,
                                      signatureFormat: ECDSAModel.SignatureFormatModel = .schnorr,
                                      unlockers: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.Transaction.UnlockerModel] = .init()) async throws -> (hash: OpalBase.Transaction.HashModel, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: OpalBase.Account.Error.tokenMintBroadcastFailed
            )
        }
    }
}
