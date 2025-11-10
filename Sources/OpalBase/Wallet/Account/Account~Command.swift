// Account~Command.swift

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
        
        fileprivate let changeEntry: Address.Book.Entry
        fileprivate let changeOutput: Transaction.Output
        fileprivate let recipientOutputs: [Transaction.Output]
        fileprivate let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        
        init(payment: Payment,
             feeRate: UInt64,
             inputs: [Transaction.Output.Unspent],
             totalSelectedAmount: Satoshi,
             targetAmount: Satoshi,
             shouldAllowDustDonation: Bool,
             changeEntry: Address.Book.Entry,
             changeOutput: Transaction.Output,
             recipientOutputs: [Transaction.Output],
             privateKeys: [Transaction.Output.Unspent: PrivateKey]) {
            self.payment = payment
            self.feeRate = feeRate
            self.inputs = inputs
            self.totalSelectedAmount = totalSelectedAmount
            self.targetAmount = targetAmount
            self.shouldAllowDustDonation = shouldAllowDustDonation
            self.changeEntry = changeEntry
            self.changeOutput = changeOutput
            self.recipientOutputs = recipientOutputs
            self.privateKeys = privateKeys
        }
        
        public func buildTransaction(signatureFormat: ECDSA.SignatureFormat = .ecdsa(.der),
                                     unlockers: [Transaction.Output.Unspent: Transaction.Unlocker] = .init()) throws -> TransactionResult {
            let transaction: Transaction
            do {
                transaction = try Transaction.build(utxoPrivateKeyPairs: privateKeys,
                                                    recipientOutputs: recipientOutputs,
                                                    changeOutput: changeOutput,
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
            
            let potentialChange = transaction.outputs.last
            let change: TransactionResult.Change?
            if let potentialChange,
               potentialChange.lockingScript == changeOutput.lockingScript,
               potentialChange.value > 0 {
                let changeAmount: Satoshi
                do {
                    changeAmount = try Satoshi(potentialChange.value)
                } catch {
                    throw Account.Error.transactionBuildFailed(error)
                }
                change = TransactionResult.Change(entry: changeEntry, amount: changeAmount)
            } else {
                change = nil
            }
            
            return TransactionResult(transaction: transaction, fee: fee, change: change)
        }
    }
    
}

extension Account {
    public func prepareSpend(_ payment: Payment,
                             feePolicy: Wallet.FeePolicy = .init()) async throws -> SpendPlan {
        guard !payment.recipients.isEmpty else { throw Error.paymentHasNoRecipients }
        
        var targetAmount = try Satoshi(0)
        for recipient in payment.recipients {
            do {
                targetAmount = try targetAmount + recipient.amount
            } catch {
                throw Error.paymentExceedsMaximumAmount
            }
        }
        
        let feeRate = feePolicy.recommendedFeeRate(for: payment.feeContext,
                                                   override: payment.feeOverride)
        let rawRecipientOutputs = payment.recipients.map { recipient in
            Transaction.Output(value: recipient.amount.uint64, address: recipient.address)
        }
        let randomizedRecipientOutputs = await privacyShaper.randomizeOutputs(rawRecipientOutputs)
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        
        let coinSelectionConfiguration = Address.Book.CoinSelection.Configuration(recipientOutputs: randomizedRecipientOutputs,
                                                                                  changeLockingScript: changeEntry.address.lockingScript.data,
                                                                                  strategy: payment.coinSelection,
                                                                                  shouldAllowDustDonation: payment.shouldAllowDustDonation)
        
        let selectedUTXOs: [Transaction.Output.Unspent]
        do {
            selectedUTXOs = try await addressBook.selectUTXOs(targetAmount: targetAmount,
                                                              feePolicy: feePolicy,
                                                              recommendationContext: payment.feeContext,
                                                              override: payment.feeOverride,
                                                              configuration: coinSelectionConfiguration)
        } catch {
            throw Error.coinSelectionFailed(error)
        }
        
        let heuristicallyOrderedInputs = await privacyShaper.applyCoinSelectionHeuristics(to: selectedUTXOs)
        
        var computedTotalSelectedValue: UInt64 = 0
        for input in heuristicallyOrderedInputs {
            let result = computedTotalSelectedValue.addingReportingOverflow(input.value)
            guard !result.overflow else { throw Error.paymentExceedsMaximumAmount }
            computedTotalSelectedValue = result.partialValue
        }
        let totalSelectedValue = computedTotalSelectedValue
        
        let totalSelectedAmount: Satoshi
        do {
            totalSelectedAmount = try Satoshi(totalSelectedValue)
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        
        guard totalSelectedAmount >= targetAmount else {
            let requiredAdditionalAmount: UInt64
            do {
                let shortfall = try targetAmount - totalSelectedAmount
                requiredAdditionalAmount = shortfall.uint64
            } catch {
                requiredAdditionalAmount = targetAmount.uint64
            }
            
            throw Error.coinSelectionFailed(Transaction.Error.insufficientFunds(required: requiredAdditionalAmount))
        }
        let changeResult = totalSelectedValue.subtractingReportingOverflow(targetAmount.uint64)
        guard !changeResult.overflow else { throw Error.paymentExceedsMaximumAmount }
        let initialChangeValue = changeResult.partialValue
        let changeOutput = Transaction.Output(value: initialChangeValue, address: changeEntry.address)
        
        let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        do {
            privateKeys = try await addressBook.derivePrivateKeys(for: heuristicallyOrderedInputs)
        } catch {
            throw Error.transactionBuildFailed(error)
        }
        
        return SpendPlan(payment: payment,
                         feeRate: feeRate,
                         inputs: heuristicallyOrderedInputs,
                         totalSelectedAmount: totalSelectedAmount,
                         targetAmount: targetAmount,
                         shouldAllowDustDonation: payment.shouldAllowDustDonation,
                         changeEntry: changeEntry,
                         changeOutput: changeOutput,
                         recipientOutputs: randomizedRecipientOutputs,
                         privateKeys: privateKeys)
    }
}
