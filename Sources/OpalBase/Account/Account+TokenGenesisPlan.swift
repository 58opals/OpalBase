// Account+TokenGenesisPlan.swift

import Foundation

extension Account {
    public struct TokenGenesisPlan: Sendable {
        public struct TransactionResult: Sendable {
            public let transaction: Transaction
            public let fee: Satoshi
            public let category: CashTokens.CategoryID
            public let mintedOutputs: [Transaction.Output]
            public let bitcoinCashChange: SpendPlan.TransactionResult.Change?
            
            public init(transaction: Transaction,
                        fee: Satoshi,
                        category: CashTokens.CategoryID,
                        mintedOutputs: [Transaction.Output],
                        bitcoinCashChange: SpendPlan.TransactionResult.Change?) {
                self.transaction = transaction
                self.fee = fee
                self.category = category
                self.mintedOutputs = mintedOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let genesis: TokenGenesis
        public let category: CashTokens.CategoryID
        public let feeRate: UInt64
        public let genesisInput: Transaction.Output.Unspent
        public let bitcoinCashInputs: [Transaction.Output.Unspent]
        public let outputs: [Transaction.Output]
        public let reservationDate: Date
        
        private let addressBook: Address.Book
        private let reservation: Address.Book.SpendReservation
        private let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        private let changeEntry: Address.Book.Entry
        private let changeOutput: Transaction.Output
        private let shouldAllowDustDonation: Bool
        private let shouldRandomizeRecipientOrdering: Bool
        private let plannedMintedOutputs: [Transaction.Output]
        
        init(genesis: TokenGenesis,
             category: CashTokens.CategoryID,
             feeRate: UInt64,
             genesisInput: Transaction.Output.Unspent,
             bitcoinCashInputs: [Transaction.Output.Unspent],
             outputs: [Transaction.Output],
             addressBook: Address.Book,
             reservation: Address.Book.SpendReservation,
             privateKeys: [Transaction.Output.Unspent: PrivateKey],
             changeEntry: Address.Book.Entry,
             changeOutput: Transaction.Output,
             plannedMintedOutputs: [Transaction.Output],
             shouldAllowDustDonation: Bool,
             shouldRandomizeRecipientOrdering: Bool) {
            self.genesis = genesis
            self.category = category
            self.feeRate = feeRate
            self.genesisInput = genesisInput
            self.bitcoinCashInputs = bitcoinCashInputs
            self.outputs = outputs
            self.reservationDate = reservation.reservationDate
            self.addressBook = addressBook
            self.reservation = reservation
            self.privateKeys = privateKeys
            self.changeEntry = changeEntry
            self.changeOutput = changeOutput
            self.plannedMintedOutputs = plannedMintedOutputs
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: ECDSA.SignatureFormat = .schnorr,
                                     unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) throws -> TransactionResult {
            let transaction: Transaction
            do {
                let outputOrderingStrategy: Transaction.OutputOrderingStrategy = shouldRandomizeRecipientOrdering ? .privacyRandomized : .canonicalBIP69
                transaction = try Transaction.build(utxoPrivateKeyPairs: privateKeys,
                                                    recipientOutputs: outputs,
                                                    changeOutput: changeOutput,
                                                    outputOrderingStrategy: outputOrderingStrategy,
                                                    signatureFormat: signatureFormat,
                                                    feePerByte: feeRate,
                                                    shouldAllowDustDonation: shouldAllowDustDonation,
                                                    unlockers: unlockers)
            } catch {
                throw Account.Error.tokenGenesisTransactionBuildFailed(error)
            }
            
            let totalOutputAmount = try transaction.outputs.sumSatoshi(or: Account.Error.paymentExceedsMaximumAmount) {
                try Satoshi($0.value)
            }
            let inputTotal = try ([genesisInput] + bitcoinCashInputs).sumSatoshi(or: Account.Error.paymentExceedsMaximumAmount) {
                try Satoshi($0.value)
            }
            let fee: Satoshi
            do {
                fee = try inputTotal - totalOutputAmount
            } catch {
                throw Account.Error.paymentExceedsMaximumAmount
            }
            
            let bitcoinCashChange: SpendPlan.TransactionResult.Change?
            do {
                bitcoinCashChange = try transaction.findBitcoinCashChange(for: changeEntry)
            } catch {
                throw Account.Error.tokenGenesisTransactionBuildFailed(error)
            }
            
            var resolver = Transaction.Output.Resolver(outputs: transaction.outputs)
            let resolvedMintedOutputs = resolver.resolve(plannedMintedOutputs)
            
            return TransactionResult(transaction: transaction,
                                     fee: fee,
                                     category: category,
                                     mintedOutputs: resolvedMintedOutputs,
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
                mapBroadcastError: Account.Error.tokenGenesisBroadcastFailed,
                onSuccess: { try await completeReservation() }
            )
        }
    }
}
