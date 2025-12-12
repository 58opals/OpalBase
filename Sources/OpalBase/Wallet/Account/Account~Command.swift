// Account~Command.swift

import Foundation

// MARK: - UTXO
extension Account {
    public func refreshUTXOSet(using service: Network.AddressReadable, usage: DerivationPath.Usage? = nil) async throws -> Address.Book.UTXORefresh {
        try await addressBook.refreshUTXOSet(using: service, usage: usage)
    }
}

// MARK: - Receive
extension Account {
    public func reserveNextReceivingEntry() async throws -> Address.Book.Entry {
        try await addressBook.reserveNextEntry(for: .receiving)
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
        let organizedRecipientOutputs = await privacyShaper.organizeOutputs(rawRecipientOutputs)
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        
        let coinSelectionConfiguration = Address.Book.CoinSelection.Configuration(recipientOutputs: organizedRecipientOutputs,
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
        let reservation: Address.Book.SpendReservation
        do {
            reservation = try await addressBook.reserveSpend(utxos: heuristicallyOrderedInputs, changeEntry: changeEntry)
        } catch {
            throw Error.coinSelectionFailed(error)
        }
        
        let reservedChangeEntry = reservation.changeEntry
        let changeOutput = Transaction.Output(value: initialChangeValue, address: reservedChangeEntry.address)
        
        let privateKeys: [Transaction.Output.Unspent: PrivateKey]
        do {
            privateKeys = try await addressBook.derivePrivateKeys(for: heuristicallyOrderedInputs)
        } catch {
            do {
                try await addressBook.releaseSpendReservation(reservation, outcome: .cancelled)
            } catch let releaseError {
                throw Error.transactionBuildFailed(releaseError)
            }
            
            throw Error.transactionBuildFailed(error)
        }
        
        return SpendPlan(payment: payment,
                         feeRate: feeRate,
                         inputs: heuristicallyOrderedInputs,
                         totalSelectedAmount: totalSelectedAmount,
                         targetAmount: targetAmount,
                         shouldAllowDustDonation: payment.shouldAllowDustDonation,
                         addressBook: addressBook,
                         changeEntry: reservedChangeEntry,
                         reservation: reservation,
                         changeOutput: changeOutput,
                         recipientOutputs: organizedRecipientOutputs,
                         privateKeys: privateKeys,
                         shouldRandomizeRecipientOrdering: privacyConfiguration.shouldRandomizeRecipientOrdering)
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

// MARK: - Monitor
extension Account {
    public func listTrackedEntries() async -> [Address.Book.Entry] {
        await addressBook.listAllEntries()
    }
}

extension Account {
    public func observeNewEntries() async -> AsyncStream<Address.Book.Entry> {
        await addressBook.observeNewEntries()
    }
}

extension Account {
    public func replaceUTXOs(for address: Address,
                             with utxos: [Transaction.Output.Unspent],
                             timestamp: Date = .now) async throws -> Satoshi {
        await addressBook.replaceUTXOs(for: address, with: utxos)
        
        if !utxos.isEmpty {
            try await addressBook.mark(address: address, isUsed: true)
        }
        
        var aggregateValue: UInt64 = 0
        for utxo in utxos {
            let (updated, didOverflow) = aggregateValue.addingReportingOverflow(utxo.value)
            if didOverflow { throw Satoshi.Error.exceedsMaximumAmount }
            aggregateValue = updated
        }
        
        let balance = try Satoshi(aggregateValue)
        try await addressBook.updateCachedBalance(for: address,
                                                  balance: balance,
                                                  timestamp: timestamp)
        return balance
    }
}

extension Account {
    public func refreshTransactionHistory(for address: Address,
                                          using service: Network.AddressReadable,
                                          includeUnconfirmed: Bool = true) async throws -> Transaction.History.ChangeSet {
        try await addressBook.refreshTransactionHistory(for: address,
                                                        using: service,
                                                        includeUnconfirmed: includeUnconfirmed)
    }
}
