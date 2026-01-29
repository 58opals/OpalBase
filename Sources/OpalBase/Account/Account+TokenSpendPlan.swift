// Account+TokenSpendPlan.swift

import Foundation

extension Account {
    public struct TokenSpendPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
            public let transaction: Transaction
            public let fee: Satoshi
            public let tokenChangeOutputs: [Transaction.Output]
            public let bitcoinCashChange: Change?
            
            public init(transaction: Transaction,
                        fee: Satoshi,
                        tokenChangeOutputs: [Transaction.Output],
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenChangeOutputs = tokenChangeOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let transfer: TokenTransfer
        public let feeRate: UInt64
        public let tokenInputs: [Transaction.Output.Unspent]
        public let bitcoinCashInputs: [Transaction.Output.Unspent]
        public let tokenRecipientOutputs: [Transaction.Output]
        public let tokenChangeOutputs: [Transaction.Output]
        public let bitcoinCashChangeOutput: Transaction.Output
        public let shouldAllowDustDonation: Bool
        public let reservationDate: Date
        
        private let addressBook: Address.Book
        private let changeEntry: Address.Book.Entry
        private let reservation: Address.Book.SpendReservation
        private let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        private let organizedTokenOutputs: [Transaction.Output]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(transfer: TokenTransfer,
             feeRate: UInt64,
             tokenInputs: [Transaction.Output.Unspent],
             bitcoinCashInputs: [Transaction.Output.Unspent],
             tokenRecipientOutputs: [Transaction.Output],
             tokenChangeOutputs: [Transaction.Output],
             bitcoinCashChangeOutput: Transaction.Output,
             shouldAllowDustDonation: Bool,
             addressBook: Address.Book,
             changeEntry: Address.Book.Entry,
             reservation: Address.Book.SpendReservation,
             privateKeys: [Transaction.Output.Unspent: PrivateKey],
             organizedTokenOutputs: [Transaction.Output],
             shouldRandomizeRecipientOrdering: Bool) {
            self.transfer = transfer
            self.feeRate = feeRate
            self.tokenInputs = tokenInputs
            self.bitcoinCashInputs = bitcoinCashInputs
            self.tokenRecipientOutputs = tokenRecipientOutputs
            self.tokenChangeOutputs = tokenChangeOutputs
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
            let inputTotal = try (tokenInputs + bitcoinCashInputs).sumSatoshi(or: Account.Error.paymentExceedsMaximumAmount) {
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
            let resolvedTokenChangeOutputs = resolver.resolve(tokenChangeOutputs)
            
            return TransactionResult(transaction: transaction,
                                     fee: fee,
                                     tokenChangeOutputs: resolvedTokenChangeOutputs,
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
            try await Transaction.BroadcastPlanner.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: Account.Error.broadcastFailed,
                onSuccess: { try await completeReservation() }
            )
        }
    }
}
