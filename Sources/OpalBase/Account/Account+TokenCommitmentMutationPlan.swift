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
        public let reservationDate: Date
        
        private let addressBook: Address.Book
        private let changeEntry: Address.Book.Entry
        private let reservation: Address.Book.SpendReservation
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
             addressBook: Address.Book,
             changeEntry: Address.Book.Entry,
             reservation: Address.Book.SpendReservation,
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
            self.reservationDate = reservation.reservationDate
            self.addressBook = addressBook
            self.changeEntry = changeEntry
            self.reservation = reservation
            self.privateKeys = privateKeys
            self.organizedTokenOutputs = organizedTokenOutputs
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: ECDSA.SignatureFormat = .schnorr,
                                     unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) throws -> TransactionResult {
            let outputOrderingStrategy: Transaction.OutputOrderingStrategy = shouldRandomizeRecipientOrdering ? .privacyRandomized : .canonicalBIP69
            let transaction: Transaction
            do {
                transaction = try Transaction.build(utxoPrivateKeyPairs: privateKeys,
                                                    recipientOutputs: organizedTokenOutputs,
                                                    changeOutput: bitcoinCashChangeOutput,
                                                    outputOrderingStrategy: outputOrderingStrategy,
                                                    signatureFormat: signatureFormat,
                                                    feePerByte: feeRate,
                                                    shouldAllowDustDonation: shouldAllowDustDonation,
                                                    unlockers: unlockers)
            } catch {
                throw Account.Error.transactionBuildFailed(error)
            }
            
            let totalOutputAmount = try transaction.outputs.sumSatoshi(or: Account.Error.paymentExceedsMaximumAmount) {
                try Satoshi($0.value)
            }
            let inputTotal = try ([authorityInput] + bitcoinCashInputs)
                .sumSatoshi(or: Account.Error.paymentExceedsMaximumAmount) {
                    try Satoshi($0.value)
                }
            let fee: Satoshi
            do {
                fee = try inputTotal - totalOutputAmount
            } catch {
                throw Account.Error.paymentExceedsMaximumAmount
            }
            
            let bitcoinCashChange: TransactionResult.Change?
            do {
                bitcoinCashChange = try transaction.findBitcoinCashChange(for: changeEntry)
            } catch {
                throw Account.Error.transactionBuildFailed(error)
            }
            
            var resolver = Transaction.Output.Resolver(outputs: transaction.outputs)
            let resolvedMutatedOutput = resolver.popFirst(matching: mutatedTokenOutput) ?? mutatedTokenOutput
            let resolvedPreservationOutput: Transaction.Output? = fungiblePreservationOutput.flatMap { resolver.popFirst(matching: $0) } ?? fungiblePreservationOutput
            
            return TransactionResult(transaction: transaction,
                                     fee: fee,
                                     mutatedTokenOutput: resolvedMutatedOutput,
                                     fungiblePreservationOutput: resolvedPreservationOutput,
                                     bitcoinCashChange: bitcoinCashChange)
        }
        
        public func completeReservation() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .completed)
        }
        
        public func cancelReservation() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
        
        public func buildAndBroadcast(via handler: Network.TransactionHandling,
                                      signatureFormat: ECDSA.SignatureFormat = .schnorr,
                                      unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) async throws -> (hash: Transaction.Hash, result: TransactionResult) {
            let transactionResult = try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers)
            
            let hash: Transaction.Hash
            do {
                hash = try await handler.broadcast(transaction: transactionResult.transaction)
            } catch {
                throw Account.Error.tokenMutationBroadcastFailed(error)
            }
            
            try await addressBook.releaseSpendReservation(reservation, outcome: .completed)
            
            return (hash: hash, result: transactionResult)
        }
    }
}
