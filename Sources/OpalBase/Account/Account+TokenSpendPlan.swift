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
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: Account.SpendReservation
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
             reservationHandle: Account.SpendReservation,
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
            let resolvedTokenChangeOutputs = resolver.resolve(tokenChangeOutputs)
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     tokenChangeOutputs: resolvedTokenChangeOutputs,
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
                mapBroadcastError: Account.Error.broadcastFailed,
                onSuccess: { try await completeReservation() }
            )
        }
    }
}
