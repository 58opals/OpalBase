// OpalBase+Account+TokenCommitmentMutationPlan.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenCommitmentMutationPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let mutatedTokenOutput: OpalBase.Transaction.OutputModel
            public let fungiblePreservationOutput: OpalBase.Transaction.OutputModel?
            public let bitcoinCashChange: Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        mutatedTokenOutput: OpalBase.Transaction.OutputModel,
                        fungiblePreservationOutput: OpalBase.Transaction.OutputModel?,
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.mutatedTokenOutput = mutatedTokenOutput
                self.fungiblePreservationOutput = fungiblePreservationOutput
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let mutation: TokenCommitmentMutation
        public let feeRate: UInt64
        public let authorityInput: OpalBase.Transaction.OutputModel.UnspentModel
        public let bitcoinCashInputs: [OpalBase.Transaction.OutputModel.UnspentModel]
        public let mutatedTokenOutput: OpalBase.Transaction.OutputModel
        public let fungiblePreservationOutput: OpalBase.Transaction.OutputModel?
        public let bitcoinCashChangeOutput: OpalBase.Transaction.OutputModel
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: OpalBase.Account.SpendReservationModel
        private let privateKeys: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey]
        private let organizedTokenOutputs: [OpalBase.Transaction.OutputModel]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(mutation: TokenCommitmentMutation,
             feeRate: UInt64,
             authorityInput: OpalBase.Transaction.OutputModel.UnspentModel,
             bitcoinCashInputs: [OpalBase.Transaction.OutputModel.UnspentModel],
             mutatedTokenOutput: OpalBase.Transaction.OutputModel,
             fungiblePreservationOutput: OpalBase.Transaction.OutputModel?,
             bitcoinCashChangeOutput: OpalBase.Transaction.OutputModel,
             shouldAllowDustDonation: Bool,
             reservationHandle: OpalBase.Account.SpendReservationModel,
             privateKeys: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey],
             organizedTokenOutputs: [OpalBase.Transaction.OutputModel],
             shouldRandomizeRecipientOrdering: Bool) {
            self.mutation = mutation
            self.feeRate = feeRate
            self.authorityInput = authorityInput
            self.bitcoinCashInputs = bitcoinCashInputs
            self.mutatedTokenOutput = mutatedTokenOutput
            self.fungiblePreservationOutput = fungiblePreservationOutput
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
            var resolver = OpalBase.Transaction.OutputModel.ResolverModel(outputs: core.transaction.outputs)
            let resolvedMutatedOutput = resolver.popFirst(matching: mutatedTokenOutput) ?? mutatedTokenOutput
            let resolvedPreservationOutput: OpalBase.Transaction.OutputModel? = fungiblePreservationOutput.flatMap { resolver.popFirst(matching: $0) } ?? fungiblePreservationOutput
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     mutatedTokenOutput: resolvedMutatedOutput,
                                     fungiblePreservationOutput: resolvedPreservationOutput,
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
                mapBroadcastError: OpalBase.Account.Error.tokenMutationBroadcastFailed
            )
        }
    }
}

