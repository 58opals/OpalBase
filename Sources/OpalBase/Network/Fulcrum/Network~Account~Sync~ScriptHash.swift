//  Network~Account~Sync~ScriptHash.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    func makeScriptHashUpdateTask(
        for accountIdentifier: Data,
        scriptHash: String,
        subscription: ScriptHashSubscription,
        options: SwiftFulcrum.Client.Call.Options
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await notification in subscription.updates {
                    await self.handleScriptHashStatus(accountIdentifier: accountIdentifier,
                                                      scriptHash: scriptHash,
                                                      status: notification.status,
                                                      options: options)
                }
                await self.handleScriptHashStreamCompletion(accountIdentifier: accountIdentifier,
                                                            scriptHash: scriptHash,
                                                            error: nil,
                                                            options: options)
            } catch {
                await self.handleScriptHashStreamCompletion(accountIdentifier: accountIdentifier,
                                                            scriptHash: scriptHash,
                                                            error: error,
                                                            options: options)
            }
        }
    }
    
    func handleScriptHashStatus(
        accountIdentifier: Data,
        scriptHash: String,
        status: String?,
        options: SwiftFulcrum.Client.Call.Options
    ) async {
        guard var state = synchronizationState(for: accountIdentifier),
              var context = state.addressContexts[scriptHash] else { return }
        
        if context.latestStatus == status {
            state.addressContexts[scriptHash] = context
            accountSynchronizationStates[accountIdentifier] = state
            return
        }
        
        context.latestStatus = status
        state.addressContexts[scriptHash] = context
        accountSynchronizationStates[accountIdentifier] = state
        
        let callOptions = state.callOptions
        await enqueueScriptHashRefresh(for: state.account,
                                       address: context.address,
                                       scriptHash: scriptHash,
                                       usage: context.usage,
                                       options: callOptions)
    }
    
    func handleScriptHashStreamCompletion(
        accountIdentifier: Data,
        scriptHash: String,
        error: Swift.Error?,
        options: SwiftFulcrum.Client.Call.Options
    ) async {
        updateScriptHashContext(for: accountIdentifier, scriptHash: scriptHash) { context in
            context.updateTask = nil
        }
        
        guard var state = synchronizationState(for: accountIdentifier),
              var context = state.addressContexts[scriptHash] else { return }
        
        if let error, !(error is CancellationError) {
            do {
                let initial = try await context.subscription.resubscribe()
                context.latestStatus = initial.status
                let callOptions = state.callOptions
                context.updateTask = makeScriptHashUpdateTask(for: accountIdentifier,
                                                              scriptHash: scriptHash,
                                                              subscription: context.subscription,
                                                              options: callOptions)
                state.addressContexts[scriptHash] = context
                accountSynchronizationStates[accountIdentifier] = state
                await handleScriptHashStatus(accountIdentifier: accountIdentifier,
                                             scriptHash: scriptHash,
                                             status: initial.status,
                                             options: callOptions)
            } catch {}
        } else {
            state.addressContexts[scriptHash] = context
            accountSynchronizationStates[accountIdentifier] = state
        }
    }
    
    func enqueueScriptHashRefresh(
        for account: Account,
        address: Address,
        scriptHash: String,
        usage: DerivationPath.Usage,
        options: SwiftFulcrum.Client.Call.Options
    ) async {
        await account.enqueueRequest(for: .refreshUTXOSet, priority: nil, retryPolicy: .retry) { [weak self, weak account] in
            guard let self, let account else { return }
            try await self.executeScriptHashRefresh(for: account,
                                                    address: address,
                                                    scriptHash: scriptHash,
                                                    usage: usage,
                                                    options: options)
        }
    }
    
    func executeScriptHashRefresh(
        for account: Account,
        address: Address,
        scriptHash: String,
        usage: DerivationPath.Usage,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws {
        try ensureSessionReady(allowRestoring: true)
        let balanceResponse = try await fetchScriptHashBalance(scriptHash, options: options)
        let balance = try makeSatoshi(confirmed: balanceResponse.confirmed, unconfirmed: balanceResponse.unconfirmed)
        let utxoResponse = try await fetchScriptHashUnspent(scriptHash, options: options)
        let utxos = try makeUnspentOutputs(from: utxoResponse.items, for: address)
        let historyResponse = try await fetchScriptHashHistory(scriptHash,
                                                               fromHeight: nil,
                                                               toHeight: nil,
                                                               includeUnconfirmed: true,
                                                               options: options)
        let historyEntries = try makeTransactionHistoryEntries(from: historyResponse.transactions)
        
        let addressBook = await account.addressBook
        let timestamp = Date()
        try await addressBook.updateCache(for: address, with: balance)
        await addressBook.replaceUTXOs(for: address, with: utxos)
        await persistUnspentOutputs(for: account)
        let changeSet = await addressBook.updateTransactionHistory(for: scriptHash,
                                                                   entries: historyEntries,
                                                                   timestamp: timestamp)
        try await applyLedgerChangeSet(changeSet,
                                       for: account,
                                       options: options,
                                       shouldVerifyTransactions: true)
        
        if !historyEntries.isEmpty || !utxos.isEmpty || balance.uint64 > 0 {
            try await addressBook.mark(address: address, isUsed: true)
            try await scanAddressGap(for: account, usage: usage, options: options)
            try await ensureAddressSubscriptions(for: account, usage: usage, options: options)
        }
    }
    
    func makeUnspentOutputs(
        from items: [SwiftFulcrum.Response.Result.Blockchain.ScriptHash.ListUnspent.Item],
        for address: Address
    ) throws -> [Transaction.Output.Unspent] {
        let lockingScript = address.lockingScript.data
        return try items.map { item in
            let transactionHashData = try Data(hexString: item.transactionHash)
            let transactionHash = Transaction.Hash(dataFromRPC: transactionHashData)
            return Transaction.Output.Unspent(value: item.value,
                                              lockingScript: lockingScript,
                                              previousTransactionHash: transactionHash,
                                              previousTransactionOutputIndex: UInt32(item.transactionPosition))
        }
    }
    
    func makeTransactionHistoryEntries(
        from transactions: [SwiftFulcrum.Response.Result.Blockchain.ScriptHash.GetHistory.Transaction]
    ) throws -> [Address.Book.History.Transaction.Entry] {
        try transactions.map { transaction in
            let transactionHashData = try Data(hexString: transaction.transactionHash)
            let transactionHash = Transaction.Hash(dataFromRPC: transactionHashData)
            return Address.Book.History.Transaction.Entry(transactionHash: transactionHash,
                                                          height: transaction.height,
                                                          fee: transaction.fee)
        }
    }
}

extension Network.FulcrumSession {
    func applyLedgerChangeSet(
        _ changeSet: Address.Book.History.Transaction.ChangeSet,
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options,
        shouldVerifyTransactions: Bool = true,
        verifier: (@Sendable (
            Account,
            [Address.Book.History.Transaction.Record],
            SwiftFulcrum.Client.Call.Options
        ) async throws -> [Address.Book.History.Transaction.Record])? = nil
    ) async throws {
        guard !changeSet.isEmpty else { return }
        var mutableChangeSet = changeSet
        if shouldVerifyTransactions {
            let recordsToVerify = changeSet.inserted + changeSet.updated
            if !recordsToVerify.isEmpty {
                let verificationClosure = verifier ?? { account, records, options in
                    try await self.verifyTransactions(for: account,
                                                      records: records,
                                                      options: options)
                }
                let verificationUpdates = try await verificationClosure(account,
                                                                        recordsToVerify,
                                                                        options)
                mutableChangeSet.applyVerificationUpdates(verificationUpdates)
            }
        }
        
        let accountIndex = await account.unhardenedIndex
        await persistLedgerRecords(mutableChangeSet.inserted, for: accountIndex)
        await persistLedgerRecords(mutableChangeSet.updated, for: accountIndex)
        
        if !mutableChangeSet.removed.isEmpty {
            let transactionHashes = mutableChangeSet.removed.map { $0.naturalOrder }
            do {
                try await storage.removeLedgerEntries(transactionHashes, for: accountIndex)
            } catch {}
        }
    }
    
    func persistLedgerRecords(_ records: [Address.Book.History.Transaction.Record],
                              for accountIndex: UInt32) async {
        guard !records.isEmpty else { return }
        for record in records {
            let entry = record.makeLedgerEntry()
            do {
                if await storage.loadLedgerEntry(for: entry.transactionHash, accountIndex: accountIndex) != nil {
                    _ = try await storage.updateLedgerEntry(entry, for: accountIndex)
                } else {
                    _ = try await storage.insertLedgerEntry(entry, for: accountIndex)
                }
            } catch {}
        }
    }
    
    func persistUnspentOutputs(for account: Account) async {
        let addressBook = await account.addressBook
        let utxos = await addressBook.listUTXOs()
        let accountIndex = await account.unhardenedIndex
        do {
            try await storage.replaceUnspentTransactionOutputs(Array(utxos), for: accountIndex)
        } catch {}
    }
}
