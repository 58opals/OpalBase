// Network~Account~Sync~Addresses.swift

import Foundation
import SwiftFulcrum

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
        _ = ensureSynchronizationState(for: account, options: options)
        
        let addressBook = await account.addressBook
        let entries = await addressBook.listEntries(for: usage)
        
        for entry in entries {
            let scriptHash = entry.address.makeScriptHash().hexadecimalString
            guard synchronizationState(for: identifier)?.addressContexts[scriptHash] == nil else { continue }
            
            let subscription = try await subscribeToScriptHash(scriptHash, options: options)
            let initial = await subscription.fetchLatestInitialResponse()
            let context = AddressContext(address: entry.address,
                                         usage: usage,
                                         scriptHash: scriptHash,
                                         subscription: subscription,
                                         updateTask: nil,
                                         latestStatus: initial.status)
            
            updateSynchronizationState(for: identifier) { state in
                state.addressContexts[scriptHash] = context
            }
            
            await handleScriptHashStatus(accountIdentifier: identifier,
                                         scriptHash: scriptHash,
                                         status: initial.status,
                                         options: options)
            
            updateScriptHashContext(for: identifier, scriptHash: scriptHash) { context in
                guard context.updateTask == nil else { return }
                context.updateTask = makeScriptHashUpdateTask(for: identifier,
                                                              scriptHash: scriptHash,
                                                              subscription: subscription,
                                                              options: options)
            }
        }
    }
}
