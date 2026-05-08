// OpalBase+Wallet+Fulcrum+Monitor~Subscription.swift

import Foundation

extension _OpalBase.Wallet.Fulcrum.Monitor {
    func registerEntry(_ entry: OpalBase.Address.Book.Entry) async {
        guard isRunning, !isFinished else { return }

        let address = entry.address
        await ensureSubscription(for: address)
        guard isRunning, !isFinished else { return }

        await dependencies.eventHub.publish(.addressTracked(address))
    }

    func startEntryObservation() async {
        guard newEntryTask == nil else { return }
        let account = dependencies.account
        newEntryTask = Task { [weak self, account] in
            let stream = await account.observeNewEntries()
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

    private func ensureSubscription(for address: OpalBase.Address) async {
        guard addressSubscriptions[address] == nil else { return }

        let startupGate = StartupGate()
        addressSubscriptions[address] = Self.makeAddressSubscriptionTask(
            for: address,
            dependencies: dependencies,
            startupGate: startupGate
        )
        await startupGate.wait()
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
                do {
                    let stream = try await reader.subscribeToAddress(address.string)
                    await startupGate?.complete()
                    do {
                        try await consumeSubscription(stream: stream, address: address, dependencies: dependencies)
                    } catch {
                        if error.isCancellationError { return }
                        guard !Task.isCancelled else { return }
                        try? await Task.sleep(for: retryDelay)
                        continue
                    }
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                } catch {
                    await startupGate?.complete()
                    if error.isCancellationError { return }
                    await publishFailure(address: address, error: error, eventHub: dependencies.eventHub)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                }
            }

            await startupGate?.complete()
        }
    }

    static func consumeSubscription(stream: AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error>,
                                    address: OpalBase.Address,
                                    dependencies: WorkerDependencies) async throws {
        do {
            for try await update in stream {
                try Task.checkCancellation()
                guard update.address == address.string else { continue }
                await handleAddressUpdate(for: address, dependencies: dependencies)
            }
        } catch {
            if error.isCancellationError {
                throw error
            }
            await handleIncrementalFailure(for: address, error: error, dependencies: dependencies)
            throw error
        }
    }

    static func handleAddressUpdate(for address: OpalBase.Address,
                                    dependencies: WorkerDependencies) async {
        do {
            let utxos = try await dependencies.addressReader.fetchUnspentOutputs(for: address.string, tokenFilter: .include)
            let historyChangeSet = try await dependencies.account.refreshTransactionHistory(for: address,
                                                                                            using: dependencies.addressReader,
                                                                                            includeUnconfirmed: dependencies.shouldIncludeUnconfirmed,
                                                                                            transactionReader: dependencies.transactionReader)
            if !historyChangeSet.isEmpty {
                await dependencies.eventHub.publish(.historyChanged(historyChangeSet))
            }
            let timestamp = Date.now
            let changeSet = try await dependencies.account.replaceUTXOs(for: address,
                                                                        with: utxos,
                                                                        timestamp: timestamp)
            await dependencies.eventHub.publish(.utxosChanged(changeSet))
        } catch {
            await handleIncrementalFailure(for: address, error: error, dependencies: dependencies)
        }
    }

    static func handleIncrementalFailure(for address: OpalBase.Address,
                                         error: Swift.Error,
                                         dependencies: WorkerDependencies) async {
        if error.isCancellationError { return }
        await publishFailure(address: address, error: error, eventHub: dependencies.eventHub)

        do {
            let utxoRefresh = try await dependencies.account.refreshUTXOSet(using: dependencies.addressReader)
            let historyChangeSet = try await dependencies.account.refreshTransactionHistory(using: dependencies.addressReader,
                                                                                            includeUnconfirmed: dependencies.shouldIncludeUnconfirmed,
                                                                                            transactionReader: dependencies.transactionReader)
            await dependencies.eventHub.publish(.performedFullRefresh(utxoRefresh, historyChangeSet))
        } catch {
            await publishFailure(address: address, error: error, eventHub: dependencies.eventHub)
        }
    }

    static func publishFailure(address: OpalBase.Address?,
                               error: Swift.Error,
                               eventHub: EventHub) async {
        await eventHub.publish(.encounteredFailure(.init(address: address, message: String(describing: error))))
    }
}
