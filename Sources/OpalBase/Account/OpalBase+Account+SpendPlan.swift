// OpalBase+Account+SpendPlan.swift

import Foundation
import OpalDiagnostics
import OpalCrypto

extension _OpalBase.Account {
    public struct SpendPlan: Sendable {
        public struct TransactionResult: Sendable {
            public struct Change: Sendable {
                public let derivedAddress: OpalBase.Account.DerivedAddress
                public let amount: OpalBase.Satoshi
                
                public init(derivedAddress: OpalBase.Account.DerivedAddress, amount: OpalBase.Satoshi) {
                    self.derivedAddress = derivedAddress
                    self.amount = amount
                }

                init(entry: OpalBase.Address.Book.Entry, amount: OpalBase.Satoshi) {
                    self.init(derivedAddress: .init(entry), amount: amount)
                }
            }
            
            public let transaction: OpalBase.Transaction
            public let fee: OpalBase.Satoshi
            public let change: Change?
            
            public init(transaction: OpalBase.Transaction, fee: OpalBase.Satoshi, change: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.change = change
            }
        }
        
        public let payment: Payment
        public let feeRate: UInt64
        public let inputs: [OpalBase.Transaction.Output.Unspent]
        public let totalSelectedAmount: OpalBase.Satoshi
        public let targetAmount: OpalBase.Satoshi
        public let shouldAllowDustDonation: Bool
        public var reservationDate: Date { reservationHandle.reservationDate }
        
        let reservationHandle: OpalBase.Account.SpendReservation
        let changeOutput: OpalBase.Transaction.Output
        let recipientOutputs: [OpalBase.Transaction.Output]
        let signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey]
        let shouldRandomizeRecipientOrdering: Bool
        
        init(payment: Payment,
             feeRate: UInt64,
             inputs: [OpalBase.Transaction.Output.Unspent],
             totalSelectedAmount: OpalBase.Satoshi,
             targetAmount: OpalBase.Satoshi,
             shouldAllowDustDonation: Bool,
             reservationHandle: OpalBase.Account.SpendReservation,
             changeOutput: OpalBase.Transaction.Output,
             recipientOutputs: [OpalBase.Transaction.Output],
             signingKeys: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey],
             shouldRandomizeRecipientOrdering: Bool) {
            self.payment = payment
            self.feeRate = feeRate
            self.inputs = inputs
            self.totalSelectedAmount = totalSelectedAmount
            self.targetAmount = targetAmount
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.reservationHandle = reservationHandle
            self.changeOutput = changeOutput
            self.recipientOutputs = recipientOutputs
            self.signingKeys = signingKeys
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: OpalBase.Transaction.SignatureFormat = .schnorr,
                                     unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker] = .init()) throws -> TransactionResult {
            try OpalDiagnostics.withTraceID {
                let fields = [
                    OpalDiagnostics.Field.operation("transaction_build"),
                    OpalDiagnostics.Field.module(),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.inputCount, inputs.count),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outputCount, recipientOutputs.count)
                ]
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.transactionBuildStarted,
                    category: OpalDiagnostics.Category.transaction,
                    fields: fields
                )

                do {
                    let core = try OpalBase.Account.buildTransactionCore(signingKeys: signingKeys,
                                                                recipientOutputs: recipientOutputs,
                                                                changeOutput: changeOutput,
                                                                feeRate: feeRate,
                                                                shouldAllowDustDonation: shouldAllowDustDonation,
                                                                shouldRandomizeRecipientOrdering: shouldRandomizeRecipientOrdering,
                                                                changeEntry: reservationHandle.changeEntry,
                                                                signatureFormat: signatureFormat,
                                                                unlockers: unlockers,
                                                                mapBuildError: OpalBase.Account.Error.transactionBuildFailed)
                    let result = TransactionResult(transaction: core.transaction, fee: core.fee, change: core.bchChange)
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.transactionBuildSucceeded,
                        category: OpalDiagnostics.Category.transaction,
                        fields: fields + [
                            OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.outputCount, result.transaction.outputs.count)
                        ]
                    )
                    return result
                } catch {
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.transactionBuildFailed,
                        category: OpalDiagnostics.Category.transaction,
                        fields: fields + OpalDiagnostics.Field.errorFields(
                            for: error,
                            fallback: OpalDiagnostics.ErrorCode.accountTransactionBuildFailed
                        )
                    )
                    throw error
                }
            }
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
            try await OpalDiagnostics.withTraceID {
                let fields = [
                    OpalDiagnostics.Field.operation("transaction_broadcast"),
                    OpalDiagnostics.Field.module(),
                    OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.inputCount, inputs.count)
                ]
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.transactionBroadcastStarted,
                    category: OpalDiagnostics.Category.transaction,
                    fields: fields
                )
                do {
                    let result = try await reservationHandle.buildAndBroadcast(
                        build: { try buildTransaction(signatureFormat: signatureFormat, unlockers: unlockers) },
                        transaction: { $0.transaction },
                        via: handler,
                        mapBroadcastError: OpalBase.Account.Error.broadcastFailed
                    )
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.transactionBroadcastSucceeded,
                        category: OpalDiagnostics.Category.transaction,
                        fields: fields
                    )
                    return result
                } catch {
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.transactionBroadcastFailed,
                        category: OpalDiagnostics.Category.transaction,
                        fields: fields + OpalDiagnostics.Field.errorFields(
                            for: error,
                            fallback: OpalDiagnostics.ErrorCode.accountBroadcastFailed
                        )
                    )
                    throw error
                }
            }
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
