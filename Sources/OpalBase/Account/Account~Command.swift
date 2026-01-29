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

// MARK: - Usage
extension Account {
    public func scanForUsedAddresses(using service: Network.AddressReadable,
                                     usage: DerivationPath.Usage? = nil,
                                     includeUnconfirmed: Bool = true) async throws -> Address.Book.UsageScan {
        try await addressBook.scanForUsedAddresses(using: service,
                                                   usage: usage,
                                                   includeUnconfirmed: includeUnconfirmed)
    }
}

// MARK: - History
extension Account {
    public func refreshTransactionHistory(using service: Network.AddressReadable,
                                          usage: DerivationPath.Usage? = nil,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: Network.TransactionReadable? = nil) async throws -> Transaction.History.ChangeSet {
        do {
            return try await addressBook.refreshTransactionHistory(using: service,
                                                                   usage: usage,
                                                                   includeUnconfirmed: includeUnconfirmed,
                                                                   transactionReader: transactionReader)
        } catch let error as Address.Book.Error {
            throw Self.makeAccountError(from: error)
        }
    }
    
    public func updateTransactionConfirmations(using handler: Network.TransactionConfirming,
                                               for transactionHashes: [Transaction.Hash]) async throws -> Transaction.History.ChangeSet {
        do {
            return try await addressBook.updateTransactionConfirmations(using: handler,
                                                                        for: transactionHashes)
        } catch let error as Address.Book.Error {
            throw Self.makeAccountError(from: error)
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
        
        if payment.recipients.contains(where: { $0.tokenData != nil }) { throw Error.paymentDoesNotSupportTokensUseTokenTransfer }
        if payment.tokenSelectionPolicy == .allowTokenUTXOs { throw Error.paymentCannotSpendTokenUTXOs }
        
        let targetAmount = try payment.recipients.sumSatoshi(or: Error.paymentExceedsMaximumAmount) { recipient in
            recipient.amount
        }
        
        let feeRate = feePolicy.recommendFeeRate(for: payment.feeContext,
                                                 override: payment.feeOverride)
        let rawRecipientOutputs = payment.recipients.map { recipient in
            Transaction.Output(value: recipient.amount.uint64,
                               address: recipient.address,
                               tokenData: nil)
        }
        let organizedRecipientOutputs = await privacyShaper.organizeOutputs(rawRecipientOutputs)
        
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        
        let coinSelectionConfiguration = Address.Book.CoinSelection.Configuration(recipientOutputs: organizedRecipientOutputs,
                                                                                  changeLockingScript: changeEntry.address.lockingScript.data,
                                                                                  strategy: payment.coinSelection,
                                                                                  shouldAllowDustDonation: payment.shouldAllowDustDonation,
                                                                                  tokenSelectionPolicy: .excludeTokenUTXOs)
        
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
        
        let totalSelectedAmount = try heuristicallyOrderedInputs.sumSatoshi(or: Error.paymentExceedsMaximumAmount) { input in
            try Satoshi(input.value)
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
        
        let initialChangeAmount: Satoshi
        do {
            initialChangeAmount = try totalSelectedAmount - targetAmount
        } catch {
            throw Error.paymentExceedsMaximumAmount
        }
        let initialChangeValue = initialChangeAmount.uint64
        
        let (reservation, reservedChangeEntry, privateKeys) = try await reserveSpendAndDeriveKeys(
            utxos: heuristicallyOrderedInputs,
            changeEntry: changeEntry,
            tokenSelectionPolicy: .excludeTokenUTXOs,
            mapReservationError: { Error.coinSelectionFailed($0) }
        )
        let reservationHandle = Account.SpendReservation(addressBook: addressBook, reservation: reservation)
        let changeOutput = Transaction.Output(value: initialChangeValue, address: reservedChangeEntry.address)
        
        return SpendPlan(payment: payment,
                         feeRate: feeRate,
                         inputs: heuristicallyOrderedInputs,
                         totalSelectedAmount: totalSelectedAmount,
                         targetAmount: targetAmount,
                         shouldAllowDustDonation: payment.shouldAllowDustDonation,
                         reservationHandle: reservationHandle,
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
        do {
            return try await handler.broadcast(transaction: transaction)
        } catch {
            throw Account.Error.broadcastFailed(error)
        }
    }
    
    public func monitorConfirmations(for transactionHash: Transaction.Hash,
                                     via handler: Network.TransactionHandling,
                                     pollInterval: Duration = .seconds(5)) -> AsyncThrowingStream<UInt?, Swift.Error> {
        let identifier = transactionHash.reverseOrder.hexadecimalString
        let fallbackInterval: Duration = .milliseconds(100)
        let effectiveInterval = pollInterval > .zero ? pollInterval : fallbackInterval
        
        return AsyncThrowingStream { continuation in
            let task = Task {
                enum ConfirmationStatus: Equatable {
                    case initial
                    case value(UInt?)
                }
                
                var lastStatus: ConfirmationStatus = .initial
                
                while !Task.isCancelled {
                    do {
                        try Task.checkCancellation()
                        
                        let confirmations: UInt?
                        do {
                            confirmations = try await handler.fetchConfirmations(forTransactionIdentifier: identifier)
                        } catch {
                            throw Account.Error.confirmationQueryFailed(error)
                        }
                        
                        let currentStatus: ConfirmationStatus = .value(confirmations)
                        if lastStatus != currentStatus {
                            continuation.yield(confirmations)
                            lastStatus = currentStatus
                        }
                        
                        do {
                            try await Task.sleep(for: effectiveInterval)
                        } catch {
                            if error.isCancellationError {
                                continuation.finish()
                                return
                            }
                            throw error
                        }
                    } catch {
                        if error.isCancellationError {
                            continuation.finish()
                            return
                        }
                        if let accountError = error as? Account.Error {
                            continuation.finish(throwing: accountError)
                            return
                        }
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
                             timestamp: Date = .now) async throws -> Address.Book.UTXOChangeSet {
        let changeSet = try await addressBook.replaceUTXOs(for: address,
                                                           with: utxos,
                                                           timestamp: timestamp)
        
        if !changeSet.updated.isEmpty {
            try await addressBook.mark(address: address, isUsed: true)
        }
        
        try await addressBook.updateCachedBalance(for: address,
                                                  balance: changeSet.balance,
                                                  timestamp: timestamp)
        return changeSet
    }
}

extension Account {
    public func refreshTransactionHistory(for address: Address,
                                          using service: Network.AddressReadable,
                                          includeUnconfirmed: Bool = true,
                                          transactionReader: Network.TransactionReadable? = nil) async throws -> Transaction.History.ChangeSet {
        try await addressBook.refreshTransactionHistory(for: address,
                                                        using: service,
                                                        includeUnconfirmed: includeUnconfirmed,
                                                        transactionReader: transactionReader)
    }
}
