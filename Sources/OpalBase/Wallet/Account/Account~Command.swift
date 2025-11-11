// Account~Command.swift

import Foundation

// MARK: - UTXO
extension Account {
    public func refreshUTXOSet(using service: Network.AddressReadable, usage: DerivationPath.Usage? = nil) async throws -> Address.Book.UTXORefresh {
        try await addressBook.refreshUTXOSet(using: service, usage: usage)
    }
}

// MARK: - History
extension Account {
    public func refreshTransactionHistory(using service: Network.AddressReadable,
                                          usage: DerivationPath.Usage? = nil,
                                          includeUnconfirmed: Bool = true) async throws -> Transaction.History.ChangeSet {
        do {
            return try await addressBook.refreshTransactionHistory(using: service,
                                                                   usage: usage,
                                                                   includeUnconfirmed: includeUnconfirmed)
        } catch let error as Address.Book.Error {
            switch error {
            case .transactionHistoryRefreshFailed(let address, let underlying):
                throw Account.Error.transactionHistoryRefreshFailed(address, underlying)
            default:
                throw error
            }
        } catch {
            throw error
        }
    }
    
    public func updateTransactionConfirmations(using handler: Network.TransactionConfirming,
                                               for transactionHashes: [Transaction.Hash]) async throws -> Transaction.History.ChangeSet {
        do {
            return try await addressBook.updateTransactionConfirmations(using: handler,
                                                                        for: transactionHashes)
        } catch let error as Address.Book.Error {
            switch error {
            case .transactionConfirmationRefreshFailed(let hash, let underlying):
                throw Account.Error.transactionConfirmationRefreshFailed(hash, underlying)
            default:
                throw error
            }
        } catch {
            throw error
        }
    }
    
    public func refreshTransactionConfirmations(using handler: Network.TransactionConfirming) async throws -> Transaction.History.ChangeSet {
        let records = await addressBook.listTransactionRecords()
        let hashes = records.map(\.transactionHash)
        guard !hashes.isEmpty else { return .init() }
        return try await updateTransactionConfirmations(using: handler, for: hashes)
    }
}

// MARK: - Spend
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

// MARK: - Broadcast
extension Account {
    public func broadcast(_ transaction: Transaction,
                          via handler: Network.TransactionHandling) async throws -> Transaction.Hash {
        let rawTransaction = transaction.encode()
        let rawTransactionHexadecimal = rawTransaction.hexadecimalString
        
        let transactionIdentifier: String
        do {
            transactionIdentifier = try await handler.broadcastTransaction(rawTransactionHexadecimal: rawTransactionHexadecimal)
        } catch {
            throw Account.Error.broadcastFailed(error)
        }
        
        let identifierData: Data
        do {
            identifierData = try Data(hexadecimalString: transactionIdentifier)
        } catch {
            throw Account.Error.broadcastFailed(error)
        }
        
        return Transaction.Hash(dataFromRPC: identifierData)
    }
    
    public func monitorConfirmations(for transactionHash: Transaction.Hash,
                                     via handler: Network.TransactionHandling,
                                     pollInterval: Duration = .seconds(5)) -> AsyncThrowingStream<UInt?, Swift.Error> {
        let identifier = transactionHash.reverseOrder.hexadecimalString
        let fallbackInterval: Duration = .milliseconds(100)
        let effectiveInterval = pollInterval > .zero ? pollInterval : fallbackInterval
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                var lastStatus: UInt?? = nil
                
                while !Task.isCancelled {
                    do {
                        try Task.checkCancellation()
                        
                        let confirmations: UInt?
                        do {
                            confirmations = try await handler.fetchConfirmations(forTransactionIdentifier: identifier)
                        } catch {
                            throw Account.Error.confirmationQueryFailed(error)
                        }
                        
                        let currentStatus: UInt?? = .some(confirmations)
                        if lastStatus == nil || lastStatus! != currentStatus {
                            lastStatus = currentStatus
                            continuation.yield(confirmations)
                        }
                        
                        do {
                            try await Task.sleep(for: effectiveInterval)
                        } catch is CancellationError {
                            continuation.finish()
                            return
                        }
                    } catch is CancellationError {
                        continuation.finish()
                        return
                    } catch let error as Account.Error {
                        continuation.finish(throwing: error)
                        return
                    } catch {
                        continuation.finish(throwing: Account.Error.confirmationQueryFailed(error))
                        return
                    }
                }
                
                continuation.finish()
            }
            
            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }
}
