// Network~HeaderChain.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    enum HeaderSynchronizationError: Swift.Error {
        case heightOverflow(UInt)
        case invalidHeader(String)
    }
}

extension Network.FulcrumSession {
    func ensureHeaderSynchronization(options: SwiftFulcrum.Client.Call.Options = .init()) async {
        do {
            try await startHeaderSynchronization(options: options)
        } catch {}
    }
    
    private func startHeaderSynchronization(options: SwiftFulcrum.Client.Call.Options) async throws {
        try ensureSessionReady(allowRestoring: true)
        
        if let existingSubscription = headerSubscription {
            if headerUpdateTask == nil {
                headerUpdateTask = makeHeaderUpdateTask(subscription: existingSubscription, options: options)
            }
            return
        }
        
        let subscriptionOptions = makeHeaderSubscriptionOptions(from: options)
        let subscription = try await subscribeToChainHeaders(options: subscriptionOptions)
        headerSubscription = subscription
        
        let initial = await subscription.fetchLatestInitialResponse()
        try await processHeader(height: initial.height, hex: initial.hex, options: options)
        
        headerUpdateTask = makeHeaderUpdateTask(subscription: subscription, options: options)
    }
    
    private func makeHeaderUpdateTask(
        subscription: Subscription<SwiftFulcrum.Response.Result.Blockchain.Headers.Subscribe, SwiftFulcrum.Response.Result.Blockchain.Headers.SubscribeNotification>,
        options: SwiftFulcrum.Client.Call.Options
    ) -> Task<Void, Never> {
        Task { [weak self] in
            guard let self else { return }
            do {
                for try await notification in subscription.updates {
                    for block in notification.blocks {
                        do {
                            try await self.processHeader(height: block.height, hex: block.hex, options: options)
                        } catch {}
                    }
                }
                await self.handleHeaderStreamCompletion(error: nil, options: options)
            } catch {
                await self.handleHeaderStreamCompletion(error: error, options: options)
            }
        }
    }
    
    private func handleHeaderStreamCompletion(
        error: Swift.Error?,
        options: SwiftFulcrum.Client.Call.Options
    ) async {
        if let error, !(error is CancellationError) {
            headerUpdateTask?.cancel()
            headerUpdateTask = nil
            headerSubscription = nil
            do {
                let subscriptionOptions = makeHeaderSubscriptionOptions(from: options)
                let subscription = try await subscribeToChainHeaders(options: subscriptionOptions)
                headerSubscription = subscription
                let initial = await subscription.fetchLatestInitialResponse()
                try await processHeader(height: initial.height, hex: initial.hex, options: options)
                headerUpdateTask = makeHeaderUpdateTask(subscription: subscription, options: options)
            } catch {
                headerSubscription = nil
                headerUpdateTask = nil
            }
        } else {
            headerUpdateTask = nil
            headerSubscription = nil
        }
    }
    
    private func processHeader(height: UInt,
                               hex: String,
                               options: SwiftFulcrum.Client.Call.Options) async throws {
        let height32 = try convertUInt(height)
        let header = try decodeHeader(hex: hex)
        let result = try await headerChain.apply(header: header, at: height32)
        await headerChain.updateTipStatus(now: Date())
        if !result.detachedHeights.isEmpty {
            await handleDetachedHeights(result.detachedHeights, options: options)
        }
        let maintenanceEvents = await headerChain.dequeueMaintenanceEvents()
        await handleHeaderMaintenanceEvents(maintenanceEvents, options: options)
    }
    
    private func makeHeaderSubscriptionOptions(
        from options: SwiftFulcrum.Client.Call.Options
    ) -> SwiftFulcrum.Client.Call.Options {
        var updated = options
        if updated.token == nil {
            updated.token = headerSynchronizationCallToken
        }
        return updated
    }
    
    private func ensureHeaders(upTo targetHeight: UInt32,
                               options: SwiftFulcrum.Client.Call.Options) async throws {
        var tip = await headerChain.currentTip()
        guard targetHeight > tip.height else { return }
        
        var nextHeight = tip.height &+ 1
        while nextHeight <= targetHeight {
            let response = try await fetchBlockHeader(at: UInt(nextHeight), options: options)
            let header = try decodeHeader(hex: response.hex)
            let result = try await headerChain.apply(header: header, at: nextHeight)
            await headerChain.updateTipStatus(now: Date())
            if !result.detachedHeights.isEmpty {
                await handleDetachedHeights(result.detachedHeights, options: options)
            }
            let events = await headerChain.dequeueMaintenanceEvents()
            await handleHeaderMaintenanceEvents(events, options: options)
            tip = await headerChain.currentTip()
            nextHeight = tip.height &+ 1
        }
    }
    
    private func decodeHeader(hex: String) throws -> Block.Header {
        let data = try Data(hexString: hex)
        let (header, bytesRead) = try Block.Header.decode(from: data)
        guard bytesRead == data.count else {
            throw HeaderSynchronizationError.invalidHeader(hex)
        }
        return header
    }
    
    private func convertUInt(_ value: UInt) throws -> UInt32 {
        guard let converted = UInt32(exactly: value) else {
            throw HeaderSynchronizationError.heightOverflow(value)
        }
        return converted
    }
    
    private func makeMerkleProof(
        from response: SwiftFulcrum.Response.Result.Blockchain.Transaction.GetMerkle
    ) throws -> Transaction.MerkleProof {
        let branch = try response.merkle.map { try Data(hexString: $0) }
        let blockHeight = try convertUInt(response.blockHeight)
        let position = try convertUInt(response.position)
        return Transaction.MerkleProof(blockHeight: blockHeight,
                                       position: position,
                                       branch: branch,
                                       blockHash: nil)
    }
    
    func verifyTransactions(
        for account: Account,
        records: [Address.Book.History.Transaction.Record],
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> [Address.Book.History.Transaction.Record] {
        guard !records.isEmpty else { return [] }
        
        var uniqueRecords: [Transaction.Hash: Address.Book.History.Transaction.Record] = .init()
        uniqueRecords.reserveCapacity(records.count)
        for record in records { uniqueRecords[record.transactionHash] = record }
        
        let addressBook = await account.addressBook
        var updatedRecords: [Address.Book.History.Transaction.Record] = .init()
        let timestamp = Date()
        
        for record in uniqueRecords.values {
            guard record.status == .confirmed else { continue }
            do {
                let hashString = record.transactionHash.reverseOrder.hexadecimalString
                let merkleResponse = try await fetchTransactionMerkleProof(forTransactionHash: hashString, options: options)
                let proof = try makeMerkleProof(from: merkleResponse)
                try await ensureHeaders(upTo: proof.blockHeight, options: options)
                
                let header: Block.Header
                if let existingHeader = await headerChain.knownHeader(at: proof.blockHeight) {
                    header = existingHeader
                } else {
                    let headerResponse = try await fetchBlockHeader(at: UInt(proof.blockHeight), options: options)
                    let decodedHeader = try decodeHeader(hex: headerResponse.hex)
                    let result = try await headerChain.apply(header: decodedHeader, at: proof.blockHeight)
                    await headerChain.updateTipStatus(now: timestamp)
                    if !result.detachedHeights.isEmpty {
                        await handleDetachedHeights(result.detachedHeights, options: options)
                    }
                    header = decodedHeader
                }
                
                let computedRoot = proof.computeRoot(for: record.transactionHash)
                let headerRoot = header.merkleRoot
                let isMatch = computedRoot == headerRoot || computedRoot == headerRoot.reversedData
                let status: Address.Book.History.Transaction.VerificationStatus = isMatch ? .verified : .conflicting
                let verifiedHeight = isMatch ? proof.blockHeight : nil
                
                if let updated = await addressBook.updateTransactionVerification(for: record.transactionHash,
                                                                                 status: status,
                                                                                 proof: proof,
                                                                                 verifiedHeight: verifiedHeight,
                                                                                 timestamp: timestamp) {
                    updatedRecords.append(updated)
                }
            } catch {
                if let pending = await addressBook.updateTransactionVerification(for: record.transactionHash,
                                                                                 status: .pending,
                                                                                 proof: nil,
                                                                                 verifiedHeight: nil,
                                                                                 timestamp: timestamp) {
                    updatedRecords.append(pending)
                }
                continue
            }
        }
        
        return updatedRecords
    }
    
    private func handleHeaderMaintenanceEvents(
        _ events: [Block.Header.Chain.MaintenanceEvent],
        options: SwiftFulcrum.Client.Call.Options
    ) async {
        guard !events.isEmpty else { return }
        for event in events {
            switch event {
            case .requiresResynchronization:
                continue
            case .staleTip:
                continue
            }
        }
    }
    
    private func handleDetachedHeights(
        _ heights: [UInt32],
        options: SwiftFulcrum.Client.Call.Options
    ) async {
        guard !heights.isEmpty else { return }
        let minimumHeight = heights.min() ?? 0
        let timestamp = Date()
        guard !accountSynchronizationStates.isEmpty else { return }
        
        for state in accountSynchronizationStates.values {
            let account = state.account
            let addressBook = await account.addressBook
            let updatedRecords = await addressBook.invalidateConfirmations(startingAt: minimumHeight,
                                                                           timestamp: timestamp)
            if !updatedRecords.isEmpty {
                let accountIndex = await account.unhardenedIndex
                await persistLedgerRecords(updatedRecords, for: accountIndex)
                var scriptHashesToRefresh: Set<String> = .init()
                for record in updatedRecords {
                    scriptHashesToRefresh.formUnion(record.scriptHashes)
                }
                
                if !scriptHashesToRefresh.isEmpty {
                    let receivingEntries = await addressBook.listEntries(for: .receiving)
                    let changeEntries = await addressBook.listEntries(for: .change)
                    var entryByScriptHash: [String: (address: Address, usage: DerivationPath.Usage)] = .init()
                    
                    for entry in receivingEntries {
                        let scriptHash = entry.address.makeScriptHash().hexadecimalString
                        entryByScriptHash[scriptHash] = (entry.address, .receiving)
                    }
                    
                    for entry in changeEntries {
                        let scriptHash = entry.address.makeScriptHash().hexadecimalString
                        entryByScriptHash[scriptHash] = (entry.address, .change)
                    }
                    
                    for scriptHash in scriptHashesToRefresh {
                        guard let entry = entryByScriptHash[scriptHash] else { continue }
                        await enqueueScriptHashRefresh(for: account,
                                                       address: entry.address,
                                                       scriptHash: scriptHash,
                                                       usage: entry.usage,
                                                       options: options)
                    }
                }
            }
        }
    }
}
