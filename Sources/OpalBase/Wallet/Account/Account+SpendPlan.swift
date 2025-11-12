// Account+SpendPlan.swift

import Foundation

extension Account {
    public struct SpendPlan: Sendable {
        public struct TransactionResult: Sendable {
            public struct Change: Sendable {
                public let entry: Address.Book.Entry
                public let amount: Satoshi
                
                public init(entry: Address.Book.Entry, amount: Satoshi) {
                    self.entry = entry
                    self.amount = amount
                }
            }
            
            public let transaction: Transaction
            public let fee: Satoshi
            public let change: Change?
            
            public init(transaction: Transaction, fee: Satoshi, change: Change?) {
                self.transaction = transaction
                self.fee = fee
                self.change = change
            }
        }
        
        public let payment: Payment
        public let feeRate: UInt64
        public let inputs: [Transaction.Output.Unspent]
        public let totalSelectedAmount: Satoshi
        public let targetAmount: Satoshi
        public let shouldAllowDustDonation: Bool
        
        fileprivate let addressBook: Address.Book
        fileprivate let changeEntry: Address.Book.Entry
        fileprivate let reservation: Address.Book.SpendReservation
        fileprivate let changeOutput: Transaction.Output
        fileprivate let recipientOutputs: [Transaction.Output]
        fileprivate let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        fileprivate let shouldRandomizeRecipientOrdering: Bool
        
        init(payment: Payment,
             feeRate: UInt64,
             inputs: [Transaction.Output.Unspent],
             totalSelectedAmount: Satoshi,
             targetAmount: Satoshi,
             shouldAllowDustDonation: Bool,
             addressBook: Address.Book,
             changeEntry: Address.Book.Entry,
             reservation: Address.Book.SpendReservation,
             changeOutput: Transaction.Output,
             recipientOutputs: [Transaction.Output],
             privateKeys: [Transaction.Output.Unspent: PrivateKey],
             shouldRandomizeRecipientOrdering: Bool) {
            self.payment = payment
            self.feeRate = feeRate
            self.inputs = inputs
            self.totalSelectedAmount = totalSelectedAmount
            self.targetAmount = targetAmount
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.addressBook = addressBook
            self.changeEntry = changeEntry
            self.reservation = reservation
            self.changeOutput = changeOutput
            self.recipientOutputs = recipientOutputs
            self.privateKeys = privateKeys
            self.shouldRandomizeRecipientOrdering = shouldRandomizeRecipientOrdering
        }
        
        public func buildTransaction(signatureFormat: ECDSA.SignatureFormat = .ecdsa(.der),
                                     unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) throws -> TransactionResult {
            let transaction: Transaction
            do {
                let outputOrderingStrategy: Transaction.OutputOrderingStrategy = shouldRandomizeRecipientOrdering ? .privacyRandomized : .canonicalBIP69
                transaction = try Transaction.build(utxoPrivateKeyPairs: privateKeys,
                                                    recipientOutputs: recipientOutputs,
                                                    changeOutput: changeOutput,
                                                    outputOrderingStrategy: outputOrderingStrategy,
                                                    signatureFormat: signatureFormat,
                                                    feePerByte: feeRate,
                                                    shouldAllowDustDonation: shouldAllowDustDonation,
                                                    unlockers: unlockers)
            } catch {
                throw Account.Error.transactionBuildFailed(error)
            }
            
            var computedTotalOutputValue: UInt64 = 0
            for output in transaction.outputs {
                let result = computedTotalOutputValue.addingReportingOverflow(output.value)
                guard !result.overflow else { throw Account.Error.paymentExceedsMaximumAmount }
                computedTotalOutputValue = result.partialValue
            }
            
            let totalOutputValue = computedTotalOutputValue
            
            var computedInputTotal: UInt64 = 0
            for input in inputs {
                let result = computedInputTotal.addingReportingOverflow(input.value)
                guard !result.overflow else { throw Account.Error.paymentExceedsMaximumAmount }
                computedInputTotal = result.partialValue
            }
            
            let inputTotal = computedInputTotal
            
            let feeDifference = inputTotal.subtractingReportingOverflow(totalOutputValue)
            guard !feeDifference.overflow else { throw Account.Error.paymentExceedsMaximumAmount }
            
            let fee: Satoshi
            do {
                fee = try Satoshi(feeDifference.partialValue)
            } catch {
                throw Account.Error.transactionBuildFailed(error)
            }
            
            let changeCandidate = transaction.outputs.first { output in
                output.lockingScript == changeOutput.lockingScript && output.value > 0
            }
            let change: TransactionResult.Change?
            if let changeCandidate {
                let changeAmount: Satoshi
                do {
                    changeAmount = try Satoshi(changeCandidate.value)
                } catch {
                    throw Account.Error.transactionBuildFailed(error)
                }
                change = TransactionResult.Change(entry: changeEntry, amount: changeAmount)
            } else {
                change = nil
            }
            
            return TransactionResult(transaction: transaction, fee: fee, change: change)
        }
        
        public func completeReservation() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .completed)
        }
        
        public func cancelReservation() async throws {
            try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
        }
    }
}
