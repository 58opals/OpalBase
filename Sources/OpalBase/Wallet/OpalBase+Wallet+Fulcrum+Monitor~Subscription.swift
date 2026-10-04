// OpalBase+Wallet+Fulcrum+Monitor~Subscription.swift

import Foundation

extension _OpalBase.Wallet.Fulcrum.Monitor {
    func registerEntry(_ entry: OpalBase.Address.Book.Entry) async {
        guard isRunning, !isFinished else { return }

        let address = entry.address
        let didRegister = await ensureSubscription(for: address)
        guard didRegister, isRunning, !isFinished else { return }

        await dependencies.eventHub.publish(.addressTracked(address))
    }

    func startEntryObservation() async {
        guard newEntryTask == nil else { return }
        let stream = await dependencies.account.observeNewEntries()
        guard isRunning, !isFinished else { return }
        newEntryTask = Task { [weak self, stream] in
            for await entry in stream {
                do {
                    try Task.checkCancellation()
                } catch {
                    return
                }
                guard let self else { return }
                await self.handleObservedEntry(entry)
            }
        }
    }

    private func handleObservedEntry(_ entry: OpalBase.Address.Book.Entry) async {
        guard isRunning else { return }
        await registerEntry(entry)
    }

    private func ensureSubscription(for address: OpalBase.Address) async -> Bool {
        guard addressSubscriptions[address] == nil else { return false }
        let startupGate = StartupGate()
        addressSubscriptions[address] = Self.makeAddressSubscriptionTask(
            for: address,
            dependencies: dependencies,
            startupGate: startupGate
        )
        await eventHub.registerAddress(address)
        await startupGate.wait()
        return true
    }
}

extension _OpalBase.Wallet.Fulcrum.Monitor {
    static func makeAddressSubscriptionTask(for address: OpalBase.Address,
                                            dependencies: WorkerDependencies,
                                            startupGate: StartupGate? = nil) -> Task<Void, Never> {
        let reader = dependencies.addressReader
        let retryDelay = dependencies.retryDelay

        return Task {
            while !Task.isCancelled {
                let generation = await dependencies.eventHub.makeMutationPermit()
                do {
                    let stream = try await reader.subscribeToAddress(address.string)
                    let subscriptionIdentifier = UUID()
                    await dependencies.eventHub.markSubscriptionReady(for: address, identifier: subscriptionIdentifier)
                    await startupGate?.complete()
                    do {
                        try await consumeSubscription(stream: stream, address: address, dependencies: dependencies, subscriptionIdentifier: subscriptionIdentifier)
                    } catch {
                        if Task.isCancelled { return }
                        await dependencies.eventHub.markSubscriptionEnded(for: address, identifier: subscriptionIdentifier)
                        guard !Task.isCancelled else { return }
                        try? await Task.sleep(for: retryDelay)
                        continue
                    }
                    guard !Task.isCancelled else { return }
                    await dependencies.eventHub.markSubscriptionEnded(for: address, identifier: subscriptionIdentifier)
                    try? await Task.sleep(for: retryDelay)
                } catch {
                    await startupGate?.complete()
                    if Task.isCancelled { return }
                    await publishFailure(address: address, error: error, eventHub: dependencies.eventHub, mutationPermit: generation)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                }
            }

            await startupGate?.complete()
        }
    }

    enum AddressUpdateEvent: Sendable {
        case notification(OpalBase.Network.AddressSubscriptionUpdate)
        case retry(OpalBase.Network.AddressSubscriptionUpdate, UUID)
    }

    static func consumeSubscription(stream: AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error>,
                                    address: OpalBase.Address,
                                    dependencies: WorkerDependencies, subscriptionIdentifier: UUID) async throws {
        let events = AsyncThrowingStream<AddressUpdateEvent, Swift.Error>.makeStream()
        let readerTask = Task {
            do {
                for try await update in stream {
                    try Task.checkCancellation()
                    events.continuation.yield(.notification(update))
                }
                await dependencies.eventHub.markSubscriptionEnded(for: address, identifier: subscriptionIdentifier)
                events.continuation.finish()
            } catch {
                await dependencies.eventHub.markSubscriptionEnded(for: address, identifier: subscriptionIdentifier)
                events.continuation.finish(throwing: error)
            }
        }
        var retryTask: Task<Void, Never>?
        var retryIdentifier: UUID?
        var lastSuccessfulHydration: (status: String?, permit: OpalBase.Network.ChainRefreshMutationPermit)?
        defer {
            retryTask?.cancel()
            readerTask.cancel()
            events.continuation.finish()
        }
        do {
            for try await event in events.stream {
                try Task.checkCancellation()
                let update: OpalBase.Network.AddressSubscriptionUpdate
                switch event {
                case .notification(let value): update = value
                case .retry(let value, let identifier):
                    guard retryIdentifier == identifier else { continue }
                    update = value
                }
                guard update.address == address.string else { continue }
                let matchingPermit = lastSuccessfulHydration?.status == update.status ? lastSuccessfulHydration?.permit : nil
                guard let permit = await dependencies.eventHub.prepareAddressUpdate(for: address,
                    subscriptionIdentifier: subscriptionIdentifier, producerGeneration: update.connectionGeneration,
                    matchingSuccessfulPermit: matchingPermit) else { continue }
                retryTask?.cancel()
                retryTask = nil
                retryIdentifier = nil
                let result = await handleAddressUpdate(for: address, dependencies: dependencies, mutationPermit: permit,
                    subscriptionIdentifier: subscriptionIdentifier)
                if let successfulPermit = result.successfulPermit {
                    lastSuccessfulHydration = (update.status, successfulPermit)
                    continue
                }
                lastSuccessfulHydration = nil
                guard result.shouldRetry, permit.isCurrent else { continue }
                // Only failed hydration schedules a retry. A new notification replaces it;
                // success, epoch invalidation, stream end, and task cancellation stop it.
                let identifier = UUID()
                retryIdentifier = identifier
                retryTask = Task {
                    do {
                        try await Task.sleep(for: dependencies.retryDelay)
                        guard permit.isCurrent else { return }
                        events.continuation.yield(.retry(update, identifier))
                    } catch { }
                }
            }
        } catch {
            if error.isCancellationError { throw error }
            await dependencies.eventHub.markSubscriptionEnded(for: address, identifier: subscriptionIdentifier)
            await handleIncrementalFailure(for: address, error: error, dependencies: dependencies)
            throw error
        }
    }

    static func handleAddressUpdate(for address: OpalBase.Address,
                                    dependencies: WorkerDependencies,
                                    mutationPermit generation: OpalBase.Network.ChainRefreshMutationPermit,
                                    subscriptionIdentifier: UUID? = nil) async -> (successfulPermit: OpalBase.Network.ChainRefreshMutationPermit?, shouldRetry: Bool) {
        do {
            try await dependencies.account.refreshMonitoringAddressChainState(
                for: address,
                using: dependencies.addressReader,
                includeUnconfirmed: dependencies.shouldIncludeUnconfirmed,
                transactionReader: dependencies.transactionReader,
                mutationPermit: generation
            ) { historyChangeSet in
                if !historyChangeSet.isEmpty {
                    await dependencies.eventHub.publish(.historyChanged(historyChangeSet), mutationPermit: generation,
                        activeSubscription: subscriptionIdentifier.map { (address, $0) })
                }
            } didRefreshUTXOs: { changeSet in
                await dependencies.eventHub.publish(.utxosChanged(changeSet), mutationPermit: generation,
                    activeSubscription: subscriptionIdentifier.map { (address, $0) })
                await dependencies.eventHub.markAddressSynchronized(address, generation: generation,
                    subscriptionIdentifier: subscriptionIdentifier)
            }
            return (await dependencies.eventHub.isCurrent(generation) ? generation : nil, false)
        } catch {
            guard await dependencies.eventHub.isCurrent(generation), !Task.isCancelled else { return (nil, false) }
            let recovered = await handleIncrementalFailure(for: address, error: error, dependencies: dependencies, mutationPermit: generation,
                subscriptionIdentifier: subscriptionIdentifier)
            return (nil, !recovered && generation.isCurrent)
        }
    }

    @discardableResult
    static func handleIncrementalFailure(for address: OpalBase.Address,
                                         error: Swift.Error,
                                         dependencies: WorkerDependencies,
                                         mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil, subscriptionIdentifier: UUID? = nil) async -> Bool {
        let generation: OpalBase.Network.ChainRefreshMutationPermit
        if let mutationPermit { generation = mutationPermit } else { generation = await dependencies.eventHub.makeMutationPermit() }
        guard generation.isCurrent, !Task.isCancelled else { return false }
        if error.isCancellationError { return false }
        await publishFailure(address: address, error: error, eventHub: dependencies.eventHub, mutationPermit: generation)

        do {
            try await dependencies.eventHub.performFullRefresh(generation: generation) {
                try await dependencies.account.refreshMonitoringChainState(
                    using: dependencies.addressReader,
                    includeUnconfirmed: dependencies.shouldIncludeUnconfirmed,
                    transactionReader: dependencies.transactionReader,
                    mutationPermit: generation
                ) { utxoRefresh, historyChangeSet in
                    await dependencies.eventHub.publish(.performedFullRefresh(utxoRefresh, historyChangeSet), mutationPermit: generation)
                }
            }
            await dependencies.eventHub.markAddressSynchronized(address, generation: generation,
                subscriptionIdentifier: subscriptionIdentifier)
            return generation.isCurrent
        } catch {
            guard generation.isCurrent, !error.isCancellationError else { return false }
            await publishFailure(address: address, error: error, eventHub: dependencies.eventHub, mutationPermit: generation)
            return false
        }
    }

    static func publishFailure(address: OpalBase.Address?,
                               error: Swift.Error,
                               eventHub: EventHub,
                               mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async {
        await eventHub.publishFailure(.init(address: address, message: String(describing: error)), mutationPermit: mutationPermit)
    }
}
