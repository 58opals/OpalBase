// Wallet+FulcrumAddress+Monitor~Subscription.swift

import Foundation

extension Wallet.FulcrumAddress.Monitor {
    func registerEntry(_ entry: Address.Book.Entry) {
        let address = entry.address
        ensureSubscription(for: address)
        publish(.addressTracked(address))
    }
    
    func startEntryObservation() async {
        guard newEntryTask == nil else { return }
        let stream = await account.observeNewEntries()
        newEntryTask = Task {
            for await entry in stream {
                try? Task.checkCancellation()
                registerEntry(entry)
            }
        }
    }
    
    private func ensureSubscription(for address: Address) {
        guard addressSubscriptions[address] == nil else { return }
        let reader = addressReader
        let retryDelay = self.retryDelay
        
        let subscriptionTask = Task {
            while !Task.isCancelled {
                do {
                    let stream = try await reader.subscribeToAddress(address.string)
                    try await consumeSubscription(stream: stream, address: address)
                } catch {
                    if error.isCancellationError { return }
                    await publishFailure(address: address, error: error)
                    guard !Task.isCancelled else { return }
                    try? await Task.sleep(for: retryDelay)
                }
            }
        }
        
        addressSubscriptions[address] = subscriptionTask
    }
    
    private func consumeSubscription(stream: AsyncThrowingStream<Network.AddressSubscriptionUpdate, any Swift.Error>,
                                     address: Address) async throws {
        do {
            for try await update in stream {
                try Task.checkCancellation()
                guard update.address == address.string else { continue }
                await handleAddressUpdate(for: address)
            }
        } catch {
            if error.isCancellationError {
                throw error
            }
            await handleIncrementalFailure(for: address, error: error)
            throw error
        }
    }
    
    private func handleAddressUpdate(for address: Address) async {
        do {
            let utxos = try await addressReader.fetchUnspentOutputs(for: address.string, tokenFilter: .include)
            let timestamp = Date.now
            let changeSet = try await account.replaceUTXOs(for: address,
                                                           with: utxos,
                                                           timestamp: timestamp)
            publish(.utxosChanged(changeSet))
            
            let historyChangeSet = try await account.refreshTransactionHistory(for: address,
                                                                               using: addressReader,
                                                                               includeUnconfirmed: shouldIncludeUnconfirmed)
            if !historyChangeSet.isEmpty {
                publish(.historyChanged(historyChangeSet))
            }
        } catch {
            await handleIncrementalFailure(for: address, error: error)
        }
    }
    
    private func handleIncrementalFailure(for address: Address, error: Swift.Error) async {
        if error.isCancellationError { return }
        await publishFailure(address: address, error: error)
        
        do {
            let utxoRefresh = try await account.refreshUTXOSet(using: addressReader)
            let historyChangeSet = try await account.refreshTransactionHistory(using: addressReader,
                                                                               includeUnconfirmed: shouldIncludeUnconfirmed)
            publish(.performedFullRefresh(utxoRefresh, historyChangeSet))
        } catch {
            await publishFailure(address: address, error: error)
        }
    }
}
