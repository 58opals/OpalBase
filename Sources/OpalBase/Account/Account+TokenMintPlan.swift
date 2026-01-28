// Account+TokenMintPlan.swift

import Foundation

extension Account {
    public struct TokenMintPlan: Sendable {
        public struct TransactionResult: Sendable {
            public struct Change: Sendable {
                public let entry: Address.Book.Entry
                public let amount: Satoshi
                
                public init(entry: Address.Book.Entry, amount: Satoshi) {
                    self.entry = entry
                    self.amount = amount
                }
            }
            
            public let transaction: Transaction
            public let fee: Satoshi
            public let tokenOutputs: [Transaction.Output]
            public let bitcoinCashChange: Change?
            
            public init(transaction: Transaction,
                        fee: Satoshi,
                        tokenOutputs: [Transaction.Output],
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenOutputs = tokenOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let mint: TokenMint
        public let feeRate: UInt64
        public let authorityInput: Transaction.Output.Unspent
        public let extraFungibleInputs: [Transaction.Output.Unspent]
        public let bitcoinCashInputs: [Transaction.Output.Unspent]
        public let tokenRecipientOutputs: [Transaction.Output]
        public let authorityReturnOutput: Transaction.Output?
        public let fungiblePreservationOutput: Transaction.Output?
        public let bitcoinCashChangeOutput: Transaction.Output
        public let shouldAllowDustDonation: Bool
        public let reservationDate: Date
        
        private let addressBook: Address.Book
        private let changeEntry: Address.Book.Entry
        private let reservation: Address.Book.SpendReservation
        private let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        private let plannedTokenOutputs: [Transaction.Output]
        private let organizedTokenOutputs: [Transaction.Output]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(mint: TokenMint,
             feeRate: UInt64,
             authorityInput: Transaction.Output.Unspent,
             extraFungibleInputs: [Transaction.Output.Unspent],
             bitcoinCashInputs: [Transaction.Output.Unspent],
             tokenRecipientOutputs: [Transaction.Output],
             authorityReturnOutput: Transaction.Output?,
             fungiblePreservationOutput: Transaction.Output?,
             bitcoinCashChangeOutput: Transaction.Output,
             shouldAllowDustDonation: Bool,
             addressBook: Address.Book,
             changeEntry: Address.Book.Entry,
             reservation: Address.Book.SpendReservation,
             privateKeys: [Transaction.Output.Unspent: PrivateKey],
             organizedTokenOutputs: [Transaction.Output],
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
            self.reservationDate = reservation.reservationDate
            self.addressBook = addressBook
            self.changeEntry = changeEntry
            self.reservation = reservation
            self.privateKeys = privateKeys
            self.plannedTokenOutputs = tokenRecipientOutputs
            + [authorityReturnOutput, fungiblePreservationOutput].compactMap { $0 }
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
            let inputTotal = try ([authorityInput] + extraFungibleInputs + bitcoinCashInputs)
                .sumSatoshi(or: Account.Error.paymentExceedsMaximumAmount) {
                    try Satoshi($0.value)
                }
            let fee: Satoshi
            do {
                fee = try inputTotal - totalOutputAmount
            } catch {
                throw Account.Error.paymentExceedsMaximumAmount
            }
            
            let bitcoinCashChangeOutput = transaction.outputs.first { output in
                output.lockingScript == changeEntry.address.lockingScript.data
                && output.tokenData == nil
                && output.value > 0
            }
            let bitcoinCashChange: TransactionResult.Change?
            if let bitcoinCashChangeOutput {
                let changeAmount: Satoshi
                do {
                    changeAmount = try Satoshi(bitcoinCashChangeOutput.value)
                } catch {
                    throw Account.Error.transactionBuildFailed(error)
                }
                bitcoinCashChange = TransactionResult.Change(entry: changeEntry, amount: changeAmount)
            } else {
                bitcoinCashChange = nil
            }
            
            var resolver = Transaction.Output.Resolver(outputs: transaction.outputs)
            let resolvedTokenOutputs = resolver.resolve(plannedTokenOutputs)
            
            return TransactionResult(transaction: transaction,
                                     fee: fee,
                                     tokenOutputs: resolvedTokenOutputs,
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
                throw Account.Error.tokenMintBroadcastFailed(error)
            }
            
            try await addressBook.releaseSpendReservation(reservation, outcome: .completed)
            
            return (hash: hash, result: transactionResult)
        }
    }
}
