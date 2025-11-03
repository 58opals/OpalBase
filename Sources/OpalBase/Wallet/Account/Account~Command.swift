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
                transaction = try Transaction.build(unspentTransactionOutputPrivateKeyPairs: privateKeys,
                                                    recipientOutputs: recipientOutputs,
                                                    changeOutput: changeOutput,
                                                    signatureFormat: signatureFormat,
                                                    feePerByte: feeRate,
                                                    shouldAllowDustDonation: shouldAllowDustDonation,
                                                    unlockers: unlockers)
            } catch {
                throw Account.Error.transactionBuildFailed(error)
            }
            
            let totalOutputValue = transaction.outputs.reduce(into: UInt64(0)) { partial, output in
                partial &+= output.value
            }
            let inputTotal = inputs.reduce(into: UInt64(0)) { partial, input in
                partial &+= input.value
            }
            
            let fee: Satoshi
            do {
                fee = try Satoshi(inputTotal &- totalOutputValue)
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
                                                                                  strategy: payment.coinSelection)
        
        let selectedUnspentTransactionOutputs: [Transaction.Output.Unspent]
        do {
            selectedUnspentTransactionOutputs = try await addressBook.selectUnspentTransactionOutputs(targetAmount: targetAmount,
                                                                                                      feePolicy: feePolicy,
                                                                                                      recommendationContext: payment.feeContext,
                                                                                                      override: payment.feeOverride,
                                                                                                      configuration: coinSelectionConfiguration)
        } catch {
            throw Error.coinSelectionFailed(error)
        }
        
        let heuristicallyOrderedInputs = await privacyShaper.applyCoinSelectionHeuristics(to: selectedUnspentTransactionOutputs)
        
        let totalSelectedValue = heuristicallyOrderedInputs.reduce(into: UInt64(0)) { partial, input in
            partial &+= input.value
        }
        guard totalSelectedValue >= targetAmount.uint64 else {
            throw Error.paymentExceedsMaximumAmount
        }
        
        let totalSelectedAmount: Satoshi
        do {
            totalSelectedAmount = try Satoshi(totalSelectedValue)
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        let initialChangeValue = totalSelectedValue &- targetAmount.uint64
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
