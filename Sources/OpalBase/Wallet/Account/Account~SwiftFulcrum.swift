// Account~SwiftFulcrum.swift

import Foundation
import SwiftFulcrum

extension Account {
    public func calculateBalance() async throws -> Satoshi {
        let addresses = await (addressBook.receivingEntries + addressBook.changeEntries).map { $0.address }
        guard !addresses.isEmpty else { return try Satoshi(0) }
        
        let fulcrum = try await fulcrumPool.acquireFulcrum()
        let total = try await withThrowingTaskGroup(of: UInt64.self) { group in
            for address in addresses {
                group.addTask {
                    let balance = try await self.addressBook.fetchBalance(for: address, using: fulcrum)
                    return balance.uint64
                }
            }
            
            var aggregate: UInt64 = 0
            for try await partial in group { aggregate += partial }
            return aggregate
        }
        
        return try Satoshi(total)
    }
    
    public func send(_ sendings: [(value: Satoshi, recipientAddress: Address)],
                     feePerByte: UInt64? = nil,
                     allowDustDonation: Bool = false,
                     strategy: Address.Book.CoinSelection = .greedyLargestFirst) async throws -> Transaction.Hash {
        let accountBalance = try await calculateBalance()
        let spendingValue = sendings.map { $0.value.uint64 }.reduce(0, +)
        guard spendingValue < accountBalance.uint64 else { throw Transaction.Error.insufficientFunds(required: spendingValue) }
        
        let selectedFeeRate: UInt64
        if let feePerByte = feePerByte {
            selectedFeeRate = feePerByte
        } else {
            let feeDecoyCount = await privacyShaper.nextDecoyCount
            let feeDecoys = await makeDecoyOperations(count: feeDecoyCount)
            selectedFeeRate = try await privacyShaper.scheduleSensitiveOperation(decoys: feeDecoys) {
                try await self.feeRate.fetchRecommendedFeeRate()
            }
        }
        
        let baseRecipientOutputs = sendings.map { Transaction.Output(value: $0.value.uint64, address: $0.recipientAddress) }
        let recipientOutputs = await privacyShaper.randomizeOutputs(baseRecipientOutputs)
        let changeEntry = try await addressBook.selectNextEntry(for: .change)
        
        let utxoDecoyCount = await privacyShaper.nextDecoyCount
        let utxoDecoys = await makeDecoyOperations(count: utxoDecoyCount)
        let selectedUTXOs = try await privacyShaper.scheduleSensitiveOperation(decoys: utxoDecoys) {
            try await self.addressBook.selectUTXOs(
                targetAmount: Satoshi(spendingValue),
                recipientOutputs: recipientOutputs,
                changeLockingScript: changeEntry.address.lockingScript.data,
                feePerByte: selectedFeeRate,
                strategy: strategy
            )
        }
        
        let utxos = await privacyShaper.applyCoinSelectionHeuristics(to: selectedUTXOs)
        let spendableValue = utxos.map { $0.value }.reduce(0, +)
        
        let privateKeyPairs = try await addressBook.derivePrivateKeys(for: utxos)
        
        let changeAddress = changeEntry.address
        let remainingValue = spendableValue - spendingValue
        
        let transaction = try Transaction.build(version: 2,
                                                utxoPrivateKeyPairs: privateKeyPairs,
                                                recipientOutputs: recipientOutputs,
                                                changeOutput: Transaction.Output(value: remainingValue, address: changeAddress),
                                                feePerByte: selectedFeeRate,
                                                allowDustDonation: allowDustDonation)
        
        let transactionData = transaction.encode()
        try await outbox.save(transactionData: transactionData)
        
        let manuallyGeneratedTransactionHash = Transaction.Hash(naturalOrder: HASH256.hash(transactionData))
        let broadcastHandle = await requestRouter.handle(for: .broadcast(manuallyGeneratedTransactionHash))
        
        let broadcastRequest: @Sendable () async throws -> Void = { [self, transaction] in
            let broadcastDecoyCount = await self.privacyShaper.nextDecoyCount
            let broadcastDecoys = await self.makeDecoyOperations(count: broadcastDecoyCount, includeFeeRateQuery: true)
            try await self.privacyShaper.scheduleSensitiveOperation(decoys: broadcastDecoys) {
                let gateway = try await self.fulcrumPool.acquireGateway()
                let response = try await gateway.broadcast(transaction)
                guard !response.originalData.isEmpty else { throw Transaction.Error.cannotBroadcastTransaction }
                await self.outbox.remove(transactionHash: response)
            }
        }
        
        if await fulcrumPool.currentStatus == .online {
            do { try await broadcastRequest() }
            catch {
                _ = await broadcastHandle.enqueue(priority: .high,
                                                  retryPolicy: .retry,
                                                  operation: broadcastRequest)
            }
        } else {
            _ = await broadcastHandle.enqueue(priority: .high,
                                              retryPolicy: .retry,
                                              operation: broadcastRequest)
        }
        
        await addressBook.handleOutgoingTransaction(transaction)
        
        return manuallyGeneratedTransactionHash
    }
    
    private func makeDecoyOperations(count: Int, includeFeeRateQuery: Bool = false) async -> [@Sendable () async -> Void] {
        guard count > 0 || includeFeeRateQuery else { return [] }
        
        var operations: [@Sendable () async -> Void] = .init()
        
        if count > 0 {
            let receivingEntries = await addressBook.listEntries(for: .receiving)
            let changeEntries = await addressBook.listEntries(for: .change)
            let addresses = (receivingEntries + changeEntries).map(\.address)
            
            if !addresses.isEmpty {
                var generator = SystemRandomNumberGenerator()
                for address in addresses.shuffled(using: &generator).prefix(count) {
                    let decoy: @Sendable () async -> Void = { [fulcrumPool, address] in
                        do {
                            let fulcrum = try await fulcrumPool.acquireFulcrum()
                            _ = try? await address.fetchBalance(includeUnconfirmed: true, using: fulcrum)
                        } catch { }
                    }
                    operations.append(decoy)
                }
            }
        }
        
        if includeFeeRateQuery {
            let decoy: @Sendable () async -> Void = { [feeRate] in
                _ = try? await feeRate.fetchRecommendedFeeRate(for: .normal)
            }
            operations.append(decoy)
        }
        
        return operations
    }
    
    public func refreshUTXOSet() async {
        let request: @Sendable () async throws -> Void = { [self] in
            let fulcrum = try await self.fulcrumPool.acquireFulcrum()
            try await self.addressBook.refreshUTXOSet(fulcrum: fulcrum)
        }
        
        do { try await request() }
        catch { await enqueueRequest(for: .refreshUTXOSet, operation: request) }
    }
    
    public func monitorBalances() async throws -> AsyncThrowingStream<Satoshi, Swift.Error> {
        let initialAddresses = await (addressBook.receivingEntries + addressBook.changeEntries).map(\.address)
        guard !initialAddresses.isEmpty else { throw Account.Monitor.Error.emptyAddresses }
        
        do {
            let fulcrum = try await fulcrumPool.acquireFulcrum()
            let (initialStream, consumerID) = try await addressMonitor.start(for: initialAddresses, using: fulcrum, through: subscriptionHub)
            let newEntryStream = await addressBook.observeNewEntries()
            
            return AsyncThrowingStream { continuation in
                Task { [weak self] in
                    guard let self else { return }
                    
                    func handle(_ stream: AsyncThrowingStream<Void, Swift.Error>) async {
                        let task = Task { [weak self] in
                            guard let self else { return }
                            do {
                                for try await _ in stream {
                                    await self.refreshUTXOSet()
                                    let balance = try await self.calculateBalance()
                                    continuation.yield(balance)
                                }
                            } catch {
                                continuation.finish(throwing: Account.Monitor.Error.monitoringFailed(error))
                            }
                        }
                        
                        await addressMonitor.storeTask(task)
                    }
                    
                    await handle(initialStream)
                    
                    let newEntryTask = Task { [weak self] in
                        guard let self else { return }
                        for await entry in newEntryStream {
                            do {
                                try await self.subscriptionHub.add(addresses: [entry.address],
                                                                   for: consumerID,
                                                                   using: fulcrum)
                            } catch {
                                continuation.finish(throwing: Account.Monitor.Error.monitoringFailed(error))
                                break
                            }
                        }
                    }
                    
                    await addressMonitor.storeTask(newEntryTask)
                    
                    continuation.onTermination = { _ in
                        
                        Task { [weak self] in
                            guard let self else { return }
                            await self.addressMonitor.stop(hub: self.subscriptionHub)
                        }
                    }
                }
            }
        } catch {
            throw Account.Monitor.Error.monitoringFailed(error)
        }
    }
    
    public func stopBalanceMonitoring() async {
        await addressMonitor.stop(hub: subscriptionHub)
    }
}

extension Account {
    public func observeNetworkStatus() async -> AsyncStream<Network.Wallet.Status> {
        await fulcrumPool.observeStatus()
    }
    
    func monitorNetworkStatus() async {
        for await status in await fulcrumPool.observeStatus() {
            switch status {
            case .online:
                await resumeQueuedRequests()
                await addressBook.resumeQueuedRequests()
                
                if let fulcrum = try? await fulcrumPool.acquireFulcrum() {
                    await addressBook.startSubscription(using: fulcrum, hub: subscriptionHub)
                    await outbox.retryPendingTransactions(using: .init(client: Adapter.SwiftFulcrum.GatewayClient(fulcrum: fulcrum)))
                }
                
            case .connecting, .offline:
                await suspendQueuedRequests()
                await addressBook.suspendQueuedRequests()
                await addressBook.stopSubscription()
            }
        }
    }
}
