// OpalBase+Account+TokenMintPlan.swift

import Foundation

extension _OpalBase.Account {
    public struct TokenMintPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let tokenOutputs: [OpalBase.Transaction.Output]
            public let bitcoinCashChange: Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        tokenOutputs: [OpalBase.Transaction.Output],
                        bitcoinCashChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenOutputs = tokenOutputs
                self.bitcoinCashChange = bitcoinCashChange
            }
        }
        
        public let mint: TokenMint
        public let feeRate: UInt64
        public let authorityInput: OpalBase.Transaction.Output.Unspent
        public let extraFungibleInputs: [OpalBase.Transaction.Output.Unspent]
        public let bitcoinCashInputs: [OpalBase.Transaction.Output.Unspent]
        public let tokenRecipientOutputs: [OpalBase.Transaction.Output]
        public let authorityReturnOutput: OpalBase.Transaction.Output?
        public let fungiblePreservationOutput: OpalBase.Transaction.Output?
        public let bitcoinCashChangeOutput: OpalBase.Transaction.Output
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: OpalBase.Account.SpendReservation
        private let privateKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.PrivateKey]
        private let plannedTokenOutputs: [OpalBase.Transaction.Output]
        private let organizedTokenOutputs: [OpalBase.Transaction.Output]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(mint: TokenMint,
             feeRate: UInt64,
             authorityInput: OpalBase.Transaction.Output.Unspent,
             extraFungibleInputs: [OpalBase.Transaction.Output.Unspent],
             bitcoinCashInputs: [OpalBase.Transaction.Output.Unspent],
             tokenRecipientOutputs: [OpalBase.Transaction.Output],
             authorityReturnOutput: OpalBase.Transaction.Output?,
             fungiblePreservationOutput: OpalBase.Transaction.Output?,
             bitcoinCashChangeOutput: OpalBase.Transaction.Output,
             shouldAllowDustDonation: Bool,
             reservationHandle: OpalBase.Account.SpendReservation,
             privateKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.PrivateKey],
             organizedTokenOutputs: [OpalBase.Transaction.Output],
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
            let resolvedTokenOutputs = OpalBase.Transaction.Output.Resolver.resolve(plannedTokenOutputs,
                                                                           in: core.transaction.outputs)
            
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
        
        public func buildAndBroadcast(via handler: OpalBase.Network.TransactionHandling,
                                      signatureFormat: OpalBase.Cryptography.SignatureFormat = .schnorr,
                                      unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) async throws -> (hash: OpalBase.Transaction.Hash, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: OpalBase.Account.Error.tokenMintBroadcastFailed
            )
        }
    }
}
