// OpalBase+Account+TokenCommitmentMutationPlan.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenCommitmentMutationPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let mutatedTokenOutput: OpalBase.Transaction.Output
            public let fungiblePreservationOutput: OpalBase.Transaction.Output?
            public let bitcoinCashChange: Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        mutatedTokenOutput: OpalBase.Transaction.Output,
                        fungiblePreservationOutput: OpalBase.Transaction.Output?,
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
        public let authorityInput: OpalBase.Transaction.Output.Unspent
        public let bitcoinCashInputs: [OpalBase.Transaction.Output.Unspent]
        public let mutatedTokenOutput: OpalBase.Transaction.Output
        public let fungiblePreservationOutput: OpalBase.Transaction.Output?
        public let bitcoinCashChangeOutput: OpalBase.Transaction.Output
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: OpalBase.Account.SpendReservation
        private let privateKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.PrivateKey]
        private let organizedTokenOutputs: [OpalBase.Transaction.Output]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(mutation: TokenCommitmentMutation,
             feeRate: UInt64,
             authorityInput: OpalBase.Transaction.Output.Unspent,
             bitcoinCashInputs: [OpalBase.Transaction.Output.Unspent],
             mutatedTokenOutput: OpalBase.Transaction.Output,
             fungiblePreservationOutput: OpalBase.Transaction.Output?,
             bitcoinCashChangeOutput: OpalBase.Transaction.Output,
             shouldAllowDustDonation: Bool,
             reservationHandle: OpalBase.Account.SpendReservation,
             privateKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.PrivateKey],
             organizedTokenOutputs: [OpalBase.Transaction.Output],
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
        
        public func buildTransaction(signatureFormat: OpalBase.Cryptography.SignatureFormat = .schnorr,
                                     unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) throws -> TransactionResult {
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
            var resolver = OpalBase.Transaction.Output.Resolver(outputs: core.transaction.outputs)
            let resolvedMutatedOutput = resolver.popFirst(matching: mutatedTokenOutput) ?? mutatedTokenOutput
            let resolvedPreservationOutput: OpalBase.Transaction.Output? = fungiblePreservationOutput.flatMap { resolver.popFirst(matching: $0) } ?? fungiblePreservationOutput
            
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
                                      signatureFormat: OpalBase.Cryptography.SignatureFormat = .schnorr,
                                      unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) async throws -> (hash: OpalBase.Transaction.Hash, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: OpalBase.Account.Error.tokenMutationBroadcastFailed
            )
        }
    }
}

