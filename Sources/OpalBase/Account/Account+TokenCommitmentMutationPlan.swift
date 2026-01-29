//  Account+TokenCommitmentMutationPlan.swift

import Foundation

extension Account {
    public struct TokenCommitmentMutationPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
            public let transaction: Transaction
            public let fee: Satoshi
            public let mutatedTokenOutput: Transaction.Output
            public let fungiblePreservationOutput: Transaction.Output?
            public let bitcoinCashChange: Change?
            
            public init(transaction: Transaction,
                        fee: Satoshi,
                        mutatedTokenOutput: Transaction.Output,
                        fungiblePreservationOutput: Transaction.Output?,
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
        public let authorityInput: Transaction.Output.Unspent
        public let bitcoinCashInputs: [Transaction.Output.Unspent]
        public let mutatedTokenOutput: Transaction.Output
        public let fungiblePreservationOutput: Transaction.Output?
        public let bitcoinCashChangeOutput: Transaction.Output
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: Account.SpendReservation
        private let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        private let organizedTokenOutputs: [Transaction.Output]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(mutation: TokenCommitmentMutation,
             feeRate: UInt64,
             authorityInput: Transaction.Output.Unspent,
             bitcoinCashInputs: [Transaction.Output.Unspent],
             mutatedTokenOutput: Transaction.Output,
             fungiblePreservationOutput: Transaction.Output?,
             bitcoinCashChangeOutput: Transaction.Output,
             shouldAllowDustDonation: Bool,
             reservationHandle: Account.SpendReservation,
             privateKeys: [Transaction.Output.Unspent: PrivateKey],
             organizedTokenOutputs: [Transaction.Output],
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
        
        public func buildTransaction(signatureFormat: ECDSA.SignatureFormat = .schnorr,
                                     unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) throws -> TransactionResult {
            let core = try Account.buildTransactionCore(privateKeys: privateKeys,
                                                        recipientOutputs: organizedTokenOutputs,
                                                        changeOutput: bitcoinCashChangeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: Account.Error.transactionBuildFailed)
            var resolver = Transaction.Output.Resolver(outputs: core.transaction.outputs)
            let resolvedMutatedOutput = resolver.popFirst(matching: mutatedTokenOutput) ?? mutatedTokenOutput
            let resolvedPreservationOutput: Transaction.Output? = fungiblePreservationOutput.flatMap { resolver.popFirst(matching: $0) } ?? fungiblePreservationOutput
            
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
        
        public func buildAndBroadcast(via handler: Network.TransactionHandling,
                                      signatureFormat: ECDSA.SignatureFormat = .schnorr,
                                      unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) async throws -> (hash: Transaction.Hash, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: Account.Error.tokenMutationBroadcastFailed
            )
        }
    }
}
