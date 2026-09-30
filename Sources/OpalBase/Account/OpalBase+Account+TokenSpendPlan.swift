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
            public let tokenOwnerBCHChange: Change?
            public let bchChange: Change?
            
            public init(transaction: OpalBase.Transaction,
                        fee: OpalBase.Satoshi,
                        tokenChangeOutputs: [OpalBase.Transaction.Output],
                        tokenOwnerBCHChange: Change? = nil,
                        bchChange: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.tokenChangeOutputs = tokenChangeOutputs
                self.tokenOwnerBCHChange = tokenOwnerBCHChange
                self.bchChange = bchChange
            }
        }

        /// A successful relay remains visible even if local reservation completion fails.
        public struct BroadcastOutcome: Sendable {
            public let hash: OpalBase.Transaction.Hash
            public let result: TransactionResult
            public let reservationCompletionError: (any Swift.Error)?
        }

        public struct ReviewedBroadcastOutcome: Sendable {
            public let hash: OpalBase.Transaction.Hash
            public let transaction: OpalBase.Transaction
            public let reservationCompletionError: (any Swift.Error)?
        }
        
        public let transfer: TokenTransfer
        public let tokenAccountIndex: UInt32
        public let bchFundingAccountIndex: UInt32
        public let feeRate: UInt64
        public let tokenInputs: [OpalBase.Transaction.Output.Unspent]
        public let bchInputs: [OpalBase.Transaction.Output.Unspent]
        public let tokenRecipientOutputs: [OpalBase.Transaction.Output]
        public let tokenChangeOutputs: [OpalBase.Transaction.Output]
        public let tokenOwnerBCHChangeOutput: OpalBase.Transaction.Output?
        public let bchChangeOutput: OpalBase.Transaction.Output
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandles.map(\.reservationDate).min() ?? .distantPast }
        
        let reservationHandles: [OpalBase.Account.SpendReservation]
        // CashCode plans use the ordinary one-account path and retain its single handle.
        var reservationHandle: OpalBase.Account.SpendReservation { reservationHandles[0] }
        let tokenOwnerChangeEntry: OpalBase.Address.Book.Entry
        let bchChangeEntry: OpalBase.Address.Book.Entry
        let signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey]
        let organizedTokenOutputs: [OpalBase.Transaction.Output]
        let shouldRandomizeRecipientOrdering: Bool
        
        init(transfer: TokenTransfer,
             tokenAccountIndex: UInt32,
             bchFundingAccountIndex: UInt32,
             feeRate: UInt64,
             tokenInputs: [OpalBase.Transaction.Output.Unspent],
             bchInputs: [OpalBase.Transaction.Output.Unspent],
             tokenRecipientOutputs: [OpalBase.Transaction.Output],
             tokenChangeOutputs: [OpalBase.Transaction.Output],
             tokenOwnerBCHChangeOutput: OpalBase.Transaction.Output?,
             bchChangeOutput: OpalBase.Transaction.Output,
             shouldAllowDustDonation: Bool,
             reservationHandles: [OpalBase.Account.SpendReservation],
             tokenOwnerChangeEntry: OpalBase.Address.Book.Entry,
             bchChangeEntry: OpalBase.Address.Book.Entry,
             signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey],
             organizedTokenOutputs: [OpalBase.Transaction.Output],
             shouldRandomizeRecipientOrdering: Bool) {
            self.transfer = transfer
            self.tokenAccountIndex = tokenAccountIndex
            self.bchFundingAccountIndex = bchFundingAccountIndex
            self.feeRate = feeRate
            self.tokenInputs = tokenInputs
            self.bchInputs = bchInputs
            self.tokenRecipientOutputs = tokenRecipientOutputs
            self.tokenChangeOutputs = tokenChangeOutputs
            self.tokenOwnerBCHChangeOutput = tokenOwnerBCHChangeOutput
            self.bchChangeOutput = bchChangeOutput
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.reservationHandles = reservationHandles
            self.tokenOwnerChangeEntry = tokenOwnerChangeEntry
            self.bchChangeEntry = bchChangeEntry
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
                                                        changeEntry: bchChangeEntry,
                                                        signatureFormat: signatureFormat,
                                                        unlockers: unlockers,
                                                        mapBuildError: OpalBase.Account.Error.transactionBuildFailed)
            let resolvedTokenChangeOutputs = OpalBase.Transaction.Output.Resolver.resolve(tokenChangeOutputs,
                                                                                 in: core.transaction.outputs)
            let tokenOwnerBCHChange: TransactionResult.Change?
            if let tokenOwnerBCHChangeOutput {
                guard let resolvedOutput = OpalBase.Transaction.Output.Resolver.resolve(
                    [tokenOwnerBCHChangeOutput],
                    in: core.transaction.outputs
                ).first else {
                    throw OpalBase.Account.Error.transactionBuildFailed(
                        OpalBase.Transaction.Error.cannotCreateTransaction
                    )
                }
                tokenOwnerBCHChange = .init(
                    entry: tokenOwnerChangeEntry,
                    amount: try OpalBase.Satoshi(resolvedOutput.value)
                )
            } else {
                tokenOwnerBCHChange = nil
            }
            
            return TransactionResult(transaction: core.transaction,
                                     fee: core.fee,
                                     tokenChangeOutputs: resolvedTokenChangeOutputs,
                                     tokenOwnerBCHChange: tokenOwnerBCHChange,
                                     bchChange: core.bchChange)
        }
        
        public func completeReservation() async throws {
            var firstError: Swift.Error?
            for handle in reservationHandles {
                do { try await handle.complete() }
                catch { if firstError == nil { firstError = error } }
            }
            if let firstError { throw firstError }
        }
        
        public func cancelReservation() async throws {
            var firstError: Swift.Error?
            for handle in reservationHandles {
                do { try await handle.cancel() }
                catch { if firstError == nil { firstError = error } }
            }
            if let firstError { throw firstError }
        }

        /// Revalidate every input owner's reservation before submitting a reviewed transaction.
        public func requireActiveReservations() async throws {
            for handle in reservationHandles {
                try await handle.requireActive()
            }
        }
        
        public func buildAndBroadcast(via handler: OpalBase.Network.TransactionClient,
                                      signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                                      unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) async throws -> (hash: OpalBase.Transaction.Hash, result: TransactionResult) {
            let outcome = try await buildAndBroadcastWithOutcome(
                via: handler,
                signatureFormat: signatureFormat,
                unlockers: unlockers
            )
            if let error = outcome.reservationCompletionError { throw error }
            return (outcome.hash, outcome.result)
        }

        /// Prefer this result when callers must distinguish accepted relay from failed local aftermath.
        public func buildAndBroadcastWithOutcome(
            via handler: OpalBase.Network.TransactionClient,
            signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()
        ) async throws -> BroadcastOutcome {
            try await requireActiveReservations()
            let result = try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers)
            let outcome = try await broadcastReviewedTransactionWithOutcome(result.transaction, via: handler)
            return BroadcastOutcome(
                hash: outcome.hash,
                result: result,
                reservationCompletionError: outcome.reservationCompletionError
            )
        }

        /// Relays the exact transaction shown in review and preserves an accepted hash if local cleanup fails.
        public func broadcastReviewedTransactionWithOutcome(
            _ transaction: OpalBase.Transaction,
            via handler: OpalBase.Network.TransactionClient
        ) async throws -> ReviewedBroadcastOutcome {
            try await requireActiveReservations()
            try validateReviewedTransaction(transaction)
            try Task.checkCancellation()
            let hash: OpalBase.Transaction.Hash
            do {
                hash = try await handler.broadcast(transaction: transaction)
            } catch {
                throw OpalBase.Account.Error.broadcastFailed(error)
            }
            do {
                try await completeReservation()
                return ReviewedBroadcastOutcome(hash: hash, transaction: transaction, reservationCompletionError: nil)
            } catch {
                return ReviewedBroadcastOutcome(hash: hash, transaction: transaction, reservationCompletionError: error)
            }
        }

        private func validateReviewedTransaction(_ transaction: OpalBase.Transaction) throws {
            var unmatchedInputs = transaction.inputs
            for selected in tokenInputs + bchInputs {
                guard let index = unmatchedInputs.firstIndex(where: {
                    $0.previousTransactionHash == selected.previousTransactionHash
                        && $0.previousTransactionOutputIndex == selected.previousTransactionOutputIndex
                }) else {
                    throw OpalBase.Account.Error.transactionBuildFailed(
                        OpalBase.Transaction.Error.cannotCreateTransaction
                    )
                }
                unmatchedInputs.remove(at: index)
            }
            guard unmatchedInputs.isEmpty else {
                throw OpalBase.Account.Error.transactionBuildFailed(
                    OpalBase.Transaction.Error.cannotCreateTransaction
                )
            }

            var unmatchedOutputs = transaction.outputs
            for planned in organizedTokenOutputs {
                guard let index = unmatchedOutputs.firstIndex(of: planned) else {
                    throw OpalBase.Account.Error.transactionBuildFailed(
                        OpalBase.Transaction.Error.cannotCreateTransaction
                    )
                }
                unmatchedOutputs.remove(at: index)
            }
            guard unmatchedOutputs.count <= 1,
                  unmatchedOutputs.allSatisfy({
                      $0.tokenData == nil
                          && $0.lockingScript == bchChangeEntry.address.lockingScript.data
                  }) else {
                throw OpalBase.Account.Error.transactionBuildFailed(
                    OpalBase.Transaction.Error.cannotCreateTransaction
                )
            }
        }

        func buildAndBroadcast(via handler: any OpalBase.Network.TransactionHandling,
                               signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                               unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) async throws -> (hash: OpalBase.Transaction.Hash, result: TransactionResult) {
            try await buildAndBroadcast(via: .init(handler),
                                        signatureFormat: signatureFormat,
                                        unlockers: unlockers)
        }

        func buildAndBroadcastWithOutcome(
            via handler: any OpalBase.Network.TransactionHandling,
            signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
            unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()
        ) async throws -> BroadcastOutcome {
            try await buildAndBroadcastWithOutcome(
                via: .init(handler),
                signatureFormat: signatureFormat,
                unlockers: unlockers
            )
        }
    }
}
