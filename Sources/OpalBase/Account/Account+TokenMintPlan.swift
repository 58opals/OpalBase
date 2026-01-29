// Account+TokenMintPlan.swift

import Foundation

extension Account {
    public struct TokenMintPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
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
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: Account.SpendReservation
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
             reservationHandle: Account.SpendReservation,
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
            self.reservationHandle = reservationHandle
            self.privateKeys = privateKeys
            self.plannedTokenOutputs = tokenRecipientOutputs
            + [authorityReturnOutput, fungiblePreservationOutput].compactMap { $0 }
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
            let resolvedTokenOutputs = resolver.resolve(plannedTokenOutputs)
            
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
        
        public func buildAndBroadcast(via handler: Network.TransactionHandling,
                                      signatureFormat: ECDSA.SignatureFormat = .schnorr,
                                      unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) async throws -> (hash: Transaction.Hash, result: TransactionResult) {
            try await Account.planBuildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: Account.Error.tokenMintBroadcastFailed,
                onSuccess: { try await completeReservation() }
            )
        }
    }
}
