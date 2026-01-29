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
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: Account.SpendReservation
        private let privateKeys: [Transaction.Output.Unspent: PrivateKey]
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
             reservationHandle: Account.SpendReservation,
             privateKeys: [Transaction.Output.Unspent: PrivateKey],
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
            self.reservationHandle = reservationHandle
            self.privateKeys = privateKeys
            self.changeOutput = changeOutput
            self.plannedMintedOutputs = plannedMintedOutputs
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: ECDSA.SignatureFormat = .schnorr,
                                     unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) throws -> TransactionResult {
            let core = try Account.buildTransactionCore(privateKeys: privateKeys,
                                                        recipientOutputs: outputs,
                                                        changeOutput: changeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: Account.Error.tokenGenesisTransactionBuildFailed)
            var resolver = Transaction.Output.Resolver(outputs: core.transaction.outputs)
            let resolvedMintedOutputs = resolver.resolve(plannedMintedOutputs)
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     category: category,
                                     mintedOutputs: resolvedMintedOutputs,
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
            try await Account.planBuildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: Account.Error.tokenGenesisBroadcastFailed,
                onSuccess: { try await completeReservation() }
            )
        }
    }
}
