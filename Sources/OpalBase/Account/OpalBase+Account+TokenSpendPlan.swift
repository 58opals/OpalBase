// OpalBase+Account+TokenSpendPlan.swift

import Foundation
import OpalCrypto

extension _OpalBase.Account {
    public struct TokenSpendPlan: Sendable {
        public struct TransactionResult: Sendable {
            public typealias Change = SpendPlan.TransactionResult.Change
            
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let tokenChangeOutputs: [OpalBase.Transaction.Output]
            public let bchChange: Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        tokenChangeOutputs: [OpalBase.Transaction.Output],
                        bchChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenChangeOutputs = tokenChangeOutputs
                self.bchChange = bchChange
            }
        }
        
        public let transfer: TokenTransfer
        public let feeRate: UInt64
        public let tokenInputs: [OpalBase.Transaction.Output.Unspent]
        public let bchInputs: [OpalBase.Transaction.Output.Unspent]
        public let tokenRecipientOutputs: [OpalBase.Transaction.Output]
        public let tokenChangeOutputs: [OpalBase.Transaction.Output]
        public let bchChangeOutput: OpalBase.Transaction.Output
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        private let reservationHandle: OpalBase.Account.SpendReservation
        private let signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey]
        private let organizedTokenOutputs: [OpalBase.Transaction.Output]
        private let shouldRandomizeRecipientOrdering: Bool
        
        init(transfer: TokenTransfer,
             feeRate: UInt64,
             tokenInputs: [OpalBase.Transaction.Output.Unspent],
             bchInputs: [OpalBase.Transaction.Output.Unspent],
             tokenRecipientOutputs: [OpalBase.Transaction.Output],
             tokenChangeOutputs: [OpalBase.Transaction.Output],
             bchChangeOutput: OpalBase.Transaction.Output,
             shouldAllowDustDonation: Bool,
             reservationHandle: OpalBase.Account.SpendReservation,
             signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey],
             organizedTokenOutputs: [OpalBase.Transaction.Output],
             shouldRandomizeRecipientOrdering: Bool) {
            self.transfer = transfer
            self.feeRate = feeRate
            self.tokenInputs = tokenInputs
            self.bchInputs = bchInputs
            self.tokenRecipientOutputs = tokenRecipientOutputs
            self.tokenChangeOutputs = tokenChangeOutputs
            self.bchChangeOutput = bchChangeOutput
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.reservationHandle = reservationHandle
            self.signingKeys = signingKeys
            self.organizedTokenOutputs = organizedTokenOutputs
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                                     unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) throws -> TransactionResult {
            let core = try OpalBase.Account.buildTransactionCore(signingKeys: signingKeys,
                                                        recipientOutputs: organizedTokenOutputs,
                                                        changeOutput: bchChangeOutput,
                                                        feeRate: feeRate,
                                                        shouldAllowDustDonation: shouldAllowDustDonation,
                                                        shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                        changeEntry: reservationHandle.changeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: OpalBase.Account.Error.transactionBuildFailed)
            let resolvedTokenChangeOutputs = OpalBase.Transaction.Output.Resolver.resolve(tokenChangeOutputs,
                                                                                 in: core.transaction.outputs)
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     tokenChangeOutputs: resolvedTokenChangeOutputs,
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
                mapBroadcastError: OpalBase.Account.Error.broadcastFailed
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
