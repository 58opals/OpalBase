// Network~Account~Sync.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    struct AccountSynchronizationState {
        var account: Account
        var callOptions: SwiftFulcrum.Client.Call.Options
        var addressContexts: [String: AddressContext]
    }
    
    struct AddressContext {
        var address: Address
        var usage: DerivationPath.Usage
        var scriptHash: String
        var subscription: Subscription<SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe, SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification>
        var updateTask: Task<Void, Never>?
        var latestStatus: String?
    }
}

extension Network.FulcrumSession {
    public func startSynchronization(
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws {
        try ensureSessionReady(allowRestoring: true)
        await ensureTelemetryInstalled(for: account)
        
        let identifier = account.id
        var state = accountSynchronizationStates[identifier]
        ?? AccountSynchronizationState(account: account,
                                       callOptions: options,
                                       addressContexts: .init())
        state.account = account
        state.callOptions = options
        accountSynchronizationStates[identifier] = state
        
        try await scanAddressGap(for: account, usage: .receiving, options: options)
        try await scanAddressGap(for: account, usage: .change, options: options)
        try await ensureAddressSubscriptions(for: account, usage: .receiving, options: options)
        try await ensureAddressSubscriptions(for: account, usage: .change, options: options)
    }
    
    public func ensureSynchronization(
        for account: Account,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async {
        do {
            try await startSynchronization(for: account, options: options)
        } catch {}
    }
    
    public func stopSynchronization(for account: Account) async {
        let identifier = account.id
        guard let state = accountSynchronizationStates.removeValue(forKey: identifier) else { return }
        
        for context in state.addressContexts.values {
            context.updateTask?.cancel()
            await context.subscription.cancel()
        }
    }
    
    func cancelAllAccountSynchronizations() async {
        guard !accountSynchronizationStates.isEmpty else { return }
        let states = accountSynchronizationStates.values
        accountSynchronizationStates.removeAll()
        for state in states {
            for context in state.addressContexts.values {
                context.updateTask?.cancel()
                await context.subscription.cancel()
            }
        }
    }
}

extension Network.FulcrumSession {
    func scanAddressGap(
        for account: Account,
        usage: DerivationPath.Usage,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws {
        let addressBook = await account.addressBook
        let gapLimit = await addressBook.readGapLimit()
        guard gapLimit > 0 else { return }
        
        var consecutiveUnused = 0
        var currentIndex = 0
        
        while consecutiveUnused < gapLimit {
            let entries = await addressBook.listEntries(for: usage)
            if currentIndex >= entries.count {
                try await addressBook.generateEntry(for: usage, isUsed: false)
                continue
            }
            
            let entry = entries[currentIndex]
            if entry.isUsed {
                consecutiveUnused = 0
                currentIndex += 1
                continue
            }
            
            let scriptHash = entry.address.makeScriptHash().hexadecimalString
            let history = try await fetchScriptHashHistory(scriptHash,
                                                           fromHeight: nil,
                                                           toHeight: nil,
                                                           includeUnconfirmed: true,
                                                           options: options)
            if history.transactions.isEmpty {
                consecutiveUnused += 1
            } else {
                consecutiveUnused = 0
                try await addressBook.mark(address: entry.address, isUsed: true)
            }
            currentIndex += 1
        }
    }
    
    func ensureAddressSubscriptions(
        for account: Account,
        usage: DerivationPath.Usage,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws {
        let identifier = account.id
        guard var state = accountSynchronizationStates[identifier] else { return }
        state.account = account
        state.callOptions = options
        accountSynchronizationStates[identifier] = state
        
        let addressBook = await account.addressBook
        let entries = await addressBook.listEntries(for: usage)
        
        for entry in entries {
            let scriptHash = entry.address.makeScriptHash().hexadecimalString
            guard state.addressContexts[scriptHash] == nil else { continue }
            
            let subscription = try await subscribeToScriptHash(scriptHash, options: options)
            let initial = await subscription.fetchLatestInitialResponse()
            
            let context = AddressContext(address: entry.address,
                                         usage: usage,
                                         scriptHash: scriptHash,
                                         subscription: subscription,
                                         updateTask: nil,
                                         latestStatus: initial.status)
            state.addressContexts[scriptHash] = context
            accountSynchronizationStates[identifier] = state
            
            await handleScriptHashStatus(accountIdentifier: identifier,
                                         scriptHash: scriptHash,
                                         status: initial.status,
                                         options: options)
            
            if var refreshedState = accountSynchronizationStates[identifier],
               var refreshedContext = refreshedState.addressContexts[scriptHash],
               refreshedContext.updateTask == nil {
                let task = makeScriptHashUpdateTask(for: identifier,
                                                    scriptHash: scriptHash,
                                                    subscription: refreshedContext.subscription,
                                                    options: options)
                refreshedContext.updateTask = task
                refreshedState.addressContexts[scriptHash] = refreshedContext
                accountSynchronizationStates[identifier] = refreshedState
                state = refreshedState
            } else if let refreshedState = accountSynchronizationStates[identifier] {
                state = refreshedState
            }
        }
    }
    
    func makeScriptHashUpdateTask(
        for accountIdentifier: Data,
        scriptHash: String,
        subscription: Subscription<SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe, SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification>,
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
        guard var state = accountSynchronizationStates[accountIdentifier],
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
        guard var state = accountSynchronizationStates[accountIdentifier],
              var context = state.addressContexts[scriptHash] else { return }
        
        context.updateTask = nil
        state.addressContexts[scriptHash] = context
        accountSynchronizationStates[accountIdentifier] = state
        
        if let error, !(error is CancellationError) {
            do {
                let initial = try await context.subscription.resubscribe()
                context.latestStatus = initial.status
                let callOptions = state.callOptions
                let task = makeScriptHashUpdateTask(for: accountIdentifier,
                                                    scriptHash: scriptHash,
                                                    subscription: context.subscription,
                                                    options: callOptions)
                context.updateTask = task
                state.addressContexts[scriptHash] = context
                accountSynchronizationStates[accountIdentifier] = state
                await handleScriptHashStatus(accountIdentifier: accountIdentifier,
                                             scriptHash: scriptHash,
                                             status: initial.status,
                                             options: callOptions)
            } catch {}
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
        try await addressBook.updateCache(for: address, with: balance)
        await addressBook.replaceUTXOs(for: address, with: utxos)
        await addressBook.updateTransactionHistory(for: scriptHash, entries: historyEntries)
        
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
