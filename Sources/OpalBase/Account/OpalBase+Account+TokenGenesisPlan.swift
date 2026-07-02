// OpalBase+Account+TokenGenesisPlan.swift

import Foundation
import OpalCrypto

extension _OpalBase.Account {
    public struct TokenGenesisPlan: Sendable {
        public struct TransactionResult: Sendable {
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let category: OpalBase.CashTokens.CategoryID
            public let mintedOutputs: [OpalBase.Transaction.Output]
            public let bchChange: SpendPlan.TransactionResult.Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        category: OpalBase.CashTokens.CategoryID,
                        mintedOutputs: [OpalBase.Transaction.Output],
                        bchChange: SpendPlan.TransactionResult.Change?) {
                self.transaction = transaction
                self.fee = fee
                self.category = category
                self.mintedOutputs = mintedOutputs
                self.bchChange = bchChange
            }
        }
        
        public let genesis: TokenGenesis
        public let category: OpalBase.CashTokens.CategoryID
        public let feeRate: UInt64
        public let genesisInput: OpalBase.Transaction.Output.Unspent
        public let bchInputs: [OpalBase.Transaction.Output.Unspent]
        public let outputs: [OpalBase.Transaction.Output]
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: OpalBase.Account.SpendReservation
        private let signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey]
        private let changeOutput: OpalBase.Transaction.Output
        private let shouldAllowDustDonation: Bool
        private let shouldRandomizeRecipientOrdering: Bool
        private let plannedMintedOutputs: [OpalBase.Transaction.Output]
        
        init(genesis: TokenGenesis,
             category: OpalBase.CashTokens.CategoryID,
             feeRate: UInt64,
             genesisInput: OpalBase.Transaction.Output.Unspent,
             bchInputs: [OpalBase.Transaction.Output.Unspent],
             outputs: [OpalBase.Transaction.Output],
             reservationHandle: OpalBase.Account.SpendReservation,
             signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey],
             changeOutput: OpalBase.Transaction.Output,
             plannedMintedOutputs: [OpalBase.Transaction.Output],
             shouldAllowDustDonation: Bool,
             shouldRandomizeRecipientOrdering: Bool) {
            self.genesis = genesis
            self.category = category
            self.feeRate = feeRate
            self.genesisInput = genesisInput
            self.bchInputs = bchInputs
            self.outputs = outputs
            self.reservationHandle = reservationHandle
            self.signingKeys = signingKeys
            self.changeOutput = changeOutput
            self.plannedMintedOutputs = plannedMintedOutputs
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                                     unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) throws -> TransactionResult {
            let core = try OpalBase.Account.buildTransactionCore(signingKeys: signingKeys,
                                                        recipientOutputs: outputs,
                                                        changeOutput: changeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: OpalBase.Account.Error.tokenGenesisTransactionBuildFailed)
            let resolvedMintedOutputs = OpalBase.Transaction.Output.Resolver.resolve(plannedMintedOutputs,
                                                                            in: core.transaction.outputs)
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     category: category,
                                     mintedOutputs: resolvedMintedOutputs,
                                     bchChange: core.bchChange)
        }
        
        public func completeReservation() async throws {
            try await reservationHandle.complete()
        }
        
        public func cancelReservation() async throws {
            try await reservationHandle.cancel()
        }
        
        public func buildAndBroadcast(via handler: OpalBase.Network.TransactionClient,
                                      signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                                      unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) async throws -> (hash: OpalBase.Transaction.Hash, result: TransactionResult) {
            try await reservationHandle.buildAndBroadcast(
                build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                transaction: { $0.transaction },
                via: handler,
                mapBroadcastError: OpalBase.Account.Error.tokenGenesisBroadcastFailed
            )
        }

        func buildAndBroadcast(via handler: any OpalBase.Network.TransactionHandling,
                               signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                               unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) async throws -> (hash: OpalBase.Transaction.Hash, result: TransactionResult) {
            try await buildAndBroadcast(via: .init(handler),
                                        signatureFormat: signatureFormat,
                                        unlockers: unlockers)
        }
    }
}
