// Account~FulcrumService.swift

import Foundation

extension Account {
    public func calculateBalance() async throws -> Satoshi {
        let addresses = await (addressBook.receivingEntries + addressBook.changeEntries).map { $0.address }
        guard !addresses.isEmpty else { return try Satoshi(0) }
        
        let service = fulcrumService
        let total = try await withThrowingTaskGroup(of: UInt64.self) { group in
            for address in addresses {
                group.addTask {
                    let balance = try await self.addressBook.fetchBalance(for: address, using: service)
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
                try await self.feeRate.fetchRecommendedFeeRate(for: .fast)
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
                let response = try await self.fulcrumService.broadcast(transaction)
                await self.outbox.remove(transactionHash: response)
            }
        }
        
        if await fulcrumService.currentStatus == .online {
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
                    let decoy: @Sendable () async -> Void = { [fulcrumService, address] in
                        _ = try? await fulcrumService.balance(for: address, includeUnconfirmed: true)
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
    
    public func refreshUTXOSet() async throws {
        let request: @Sendable () async throws -> Void = { [self] in
            try await self.addressBook.refreshUTXOSet(service: self.fulcrumService)
        }
        
        do { try await request() }
        catch { await enqueueRequest(for: .refreshUTXOSet, operation: request) }
    }
    
    func makeBalanceStream() async throws -> AsyncThrowingStream<Satoshi, Swift.Error> {
        let addresses = await (addressBook.receivingEntries + addressBook.changeEntries).map(\.address)
        guard !addresses.isEmpty else { throw Network.Account.Lifecycle.Error.emptyAddresses }
        
        let consumerID = UUID()
        balanceMonitorConsumerID = consumerID
        isBalanceMonitoringSuspended = false
        
        let streamHandle = try await subscriptionHub.makeStream(for: addresses,
                                                                using: fulcrumService,
                                                                consumerID: consumerID)
        let newEntryStream = await addressBook.observeNewEntries()
        
        return AsyncThrowingStream { continuation in
            self.balanceMonitorContinuation = continuation
            
            let notificationTask = Task { [weak self] in
                guard let self else { return }
                defer { Task { await self.cleanupBalanceMonitoring(removeConsumer: true) } }
                
                do {
                    for try await _ in streamHandle.eventStream {
                        await self.handleBalanceNotification(continuation: continuation)
                    }
                    
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Network.Account.Lifecycle.Error.monitoringFailed(error))
                }
            }
            
            balanceMonitorTasks.append(notificationTask)
            
            let newEntryTask = Task { [weak self] in
                guard let self else { return }
                for await entry in newEntryStream {
                    do {
                        try await self.subscriptionHub.add(addresses: [entry.address],
                                                           for: consumerID,
                                                           using: self.fulcrumService)
                    } catch {
                        continuation.finish(throwing: Network.Account.Lifecycle.Error.monitoringFailed(error))
                        break
                    }
                }
            }
            
            balanceMonitorTasks.append(newEntryTask)
            
            continuation.onTermination = { _ in
                Task { [weak self] in
                    await self?.cleanupBalanceMonitoring(removeConsumer: true)
                }
            }
        }
    }
    
    func suspendBalanceStream() async throws {
        guard balanceMonitorContinuation != nil else { return }
        isBalanceMonitoringSuspended = true
        balanceMonitorDebounceTask?.cancel()
        balanceMonitorDebounceTask = nil
    }
    
    func resumeBalanceStream() async throws {
        guard let continuation = balanceMonitorContinuation else { return }
        isBalanceMonitoringSuspended = false
        
        do {
            try await refreshUTXOSet()
            let balance = try await calculateBalance()
            continuation.yield(balance)
        } catch let lifecycleError as Network.Account.Lifecycle.Error {
            throw lifecycleError
        } catch {
            throw Network.Account.Lifecycle.Error.monitoringFailed(error)
        }
    }
    
    func shutdownBalanceStream() async throws {
        await cleanupBalanceMonitoring(removeConsumer: true)
    }
}

extension Account {
    public func observeNetworkStatus() async -> AsyncStream<Network.Wallet.Status> {
        await fulcrumService.observeStatus()
    }
    
    func monitorNetworkStatus() async {
        for await status in await fulcrumService.observeStatus() {
            switch status {
            case .online:
                await resumeQueuedRequests()
                await addressBook.resumeQueuedRequests()
                
                do { try await resumeBalanceMonitoring() }
                catch { }
                
                await addressBook.startSubscription(using: fulcrumService, hub: subscriptionHub)
                await outbox.retryPendingTransactions(using: fulcrumService)
                
            case .connecting, .offline:
                await suspendQueuedRequests()
                await addressBook.suspendQueuedRequests()
                await addressBook.stopSubscription()
                
                do { try await suspendBalanceMonitoring() }
                catch { }
            }
        }
    }
}

private extension Account {
    func handleBalanceNotification(
        continuation: AsyncThrowingStream<Satoshi, Swift.Error>.Continuation
    ) async {
        guard !isBalanceMonitoringSuspended else { return }
        
        balanceMonitorDebounceTask?.cancel()
        balanceMonitorDebounceTask = Task { [weak self] in
            guard let self else { return }
            
            do {
                try await Task.sleep(nanoseconds: balanceMonitorDebounceInterval)
                try await self.refreshUTXOSet()
                let balance = try await self.calculateBalance()
                continuation.yield(balance)
            } catch is CancellationError {
                return
            } catch let lifecycleError as Network.Account.Lifecycle.Error {
                continuation.finish(throwing: lifecycleError)
            } catch {
                continuation.finish(throwing: Network.Account.Lifecycle.Error.monitoringFailed(error))
            }
        }
    }
    
    func cleanupBalanceMonitoring(removeConsumer: Bool) async {
        balanceMonitorDebounceTask?.cancel()
        balanceMonitorDebounceTask = nil
        
        for task in balanceMonitorTasks { task.cancel() }
        balanceMonitorTasks.removeAll()
        
        if removeConsumer, let consumerID = balanceMonitorConsumerID {
            await subscriptionHub.remove(consumerID: consumerID)
        }
        
        balanceMonitorConsumerID = nil
        balanceMonitorContinuation = nil
        isBalanceMonitoringSuspended = false
    }
}
