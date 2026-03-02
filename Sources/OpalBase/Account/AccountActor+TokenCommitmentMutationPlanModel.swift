//  AccountActor+TokenCommitmentMutationPlanModel.swift

import Foundation
import OpalCrypto

extension AccountActor {
    public struct TokenCommitmentMutationPlanModel: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlanModel.TransactionResult.Change
            
            public let transaction: TransactionModel
            public let fee: SatoshiModel
            public let mutatedTokenOutput: TransactionModel.OutputModel
            public let fungiblePreservationOutput: TransactionModel.OutputModel?
            public let bitcoinCashChange: Change?
            
            public init(transaction: TransactionModel,
                        fee: SatoshiModel,
                        mutatedTokenOutput: TransactionModel.OutputModel,
                        fungiblePreservationOutput: TransactionModel.OutputModel?,
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.mutatedTokenOutput = mutatedTokenOutput
                self.fungiblePreservationOutput = fungiblePreservationOutput
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let mutation: TokenCommitmentMutationModel
        public let feeRate: UInt64
        public let authorityInput: TransactionModel.OutputModel.UnspentModel
        public let bitcoinCashInputs: [TransactionModel.OutputModel.UnspentModel]
        public let mutatedTokenOutput: TransactionModel.OutputModel
        public let fungiblePreservationOutput: TransactionModel.OutputModel?
        public let bitcoinCashChangeOutput: TransactionModel.OutputModel
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: AccountActor.SpendReservationModel
        private let privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel]
        private let organizedTokenOutputs: [TransactionModel.OutputModel]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(mutation: TokenCommitmentMutationModel,
             feeRate: UInt64,
             authorityInput: TransactionModel.OutputModel.UnspentModel,
             bitcoinCashInputs: [TransactionModel.OutputModel.UnspentModel],
             mutatedTokenOutput: TransactionModel.OutputModel,
             fungiblePreservationOutput: TransactionModel.OutputModel?,
             bitcoinCashChangeOutput: TransactionModel.OutputModel,
             shouldAllowDustDonation: Bool,
             reservationHandle: AccountActor.SpendReservationModel,
             privateKeys: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
             organizedTokenOutputs: [TransactionModel.OutputModel],
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
        
        public func buildTransaction(signatureFormat: EllipticCurveDigitalSignatureAlgorithmModel.SignatureFormatModel = .schnorr,
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
            var resolver = TransactionModel.OutputModel.ResolverModel(outputs: core.transaction.outputs)
            let resolvedMutatedOutput = resolver.popFirst(matching: mutatedTokenOutput) ?? mutatedTokenOutput
            let resolvedPreservationOutput: TransactionModel.OutputModel? = fungiblePreservationOutput.flatMap { resolver.popFirst(matching: $0) } ?? fungiblePreservationOutput
            
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
        
        public func buildAndBroadcast(via handler: NetworkModel.TransactionHandling,
                                      signatureFormat: EllipticCurveDigitalSignatureAlgorithmModel.SignatureFormatModel = .schnorr,
                                      unlockers: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel] = .init()) async throws -> (hash: TransactionModel.HashModel, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: AccountActor.Error.tokenMutationBroadcastFailed
            )
        }
    }
}
