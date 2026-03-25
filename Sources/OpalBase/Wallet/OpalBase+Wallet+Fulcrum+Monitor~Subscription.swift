// OpalBase+Wallet+Fulcrum+Monitor~Subscription.swift

import Foundation

extension _OpalBase.Wallet.Fulcrum.Monitor {
    func registerEntry(_ entry: OpalBase.Address.Book.Entry) {
        let address = entry.address
        ensureSubscription(for: address)
        relay.publish(.addressTracked(address))
    }

    func startEntryObservation() async {
        guard newEntryTask == nil else { return }
        let account = dependencies.account
        newEntryTask = Task.detached { [weak self] in
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

    private func handleObservedEntry(_ entry: OpalBase.Address.Book.Entry) {
        guard isRunning else { return }
        registerEntry(entry)
    }

    private func ensureSubscription(for address: OpalBase.Address) {
        guard addressSubscriptions[address] == nil else { return }
        addressSubscriptions[address] = Self.makeAddressSubscriptionTask(for: address, dependencies: dependencies)
    }
}

extension _OpalBase.Wallet.Fulcrum.Monitor {
    static func makeAddressSubscriptionTask(for address: OpalBase.Address,
                                            dependencies: WorkerDependencies) -> Task<Void, Never> {
        let reader = dependencies.addressReader
        let retryDelay = dependencies.retryDelay

        return Task.detached {
            while !Task.isCancelled {
                do {
                    let stream = try await reader.subscribeToAddress(address.string)
                    try await consumeSubscription(stream: stream, address: address, dependencies: dependencies)
                } catch {
                    if error.isCancellationError { return }
                    publishFailure(address: address, error: error, relay: dependencies.relay)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                }
            }
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
            let timestamp = Date.now
            let changeSet = try await dependencies.account.replaceUTXOs(for: address,
                                                                        with: utxos,
                                                                        timestamp: timestamp)
            dependencies.relay.publish(.utxosChanged(changeSet))

            let historyChangeSet = try await dependencies.account.refreshTransactionHistory(for: address,
                                                                                            using: dependencies.addressReader,
                                                                                            includeUnconfirmed: dependencies.shouldIncludeUnconfirmed,
                                                                                            transactionReader: dependencies.transactionReader)
            if !historyChangeSet.isEmpty {
                dependencies.relay.publish(.historyChanged(historyChangeSet))
            }
        } catch {
            await handleIncrementalFailure(for: address, error: error, dependencies: dependencies)
        }
    }

    static func handleIncrementalFailure(for address: OpalBase.Address,
                                         error: Swift.Error,
                                         dependencies: WorkerDependencies) async {
        if error.isCancellationError { return }
        publishFailure(address: address, error: error, relay: dependencies.relay)

        do {
            let utxoRefresh = try await dependencies.account.refreshUTXOSet(using: dependencies.addressReader)
            let historyChangeSet = try await dependencies.account.refreshTransactionHistory(using: dependencies.addressReader,
                                                                                            includeUnconfirmed: dependencies.shouldIncludeUnconfirmed,
                                                                                            transactionReader: dependencies.transactionReader)
            dependencies.relay.publish(.performedFullRefresh(utxoRefresh, historyChangeSet))
        } catch {
            publishFailure(address: address, error: error, relay: dependencies.relay)
        }
    }

    static func publishFailure(address: OpalBase.Address?,
                               error: Swift.Error,
                               relay: EventRelay) {
        relay.publish(.encounteredFailure(.init(address: address, message: String(describing: error))))
    }
}
