// Wallet+FulcrumAddress+Monitor~Subscription.swift

import Foundation

extension Wallet.FulcrumAddress.Monitor {
    func registerEntry(_ entry: Address.Book.Entry) {
        let address = entry.address
        ensureSubscription(for: address)
        publish(.addressMonitored(address))
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
                    if error is CancellationError { return }
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
        } catch let error as CancellationError {
            throw error
        } catch {
            await handleIncrementalFailure(for: address, error: error)
            throw error
        }
    }
    
    private func handleAddressUpdate(for address: Address) async {
        do {
            let utxos = try await addressReader.fetchUnspentOutputs(for: address.string)
            let balance = try await account.replaceUTXOs(for: address,
                                                         with: utxos,
                                                         timestamp: .now)
            publish(.utxosUpdated(address: address, balance: balance, utxos: utxos))
            
            let changeSet = try await account.refreshTransactionHistory(for: address,
                                                                        using: addressReader,
                                                                        includeUnconfirmed: includeUnconfirmed)
            if !changeSet.isEmpty {
                publish(.historyChanged(changeSet))
            }
        } catch {
            await handleIncrementalFailure(for: address, error: error)
        }
    }
    
    private func handleIncrementalFailure(for address: Address, error: Swift.Error) async {
        if error is CancellationError { return }
        await publishFailure(address: address, error: error)
        
        do {
            let utxoRefresh = try await account.refreshUTXOSet(using: addressReader)
            let historyChangeSet = try await account.refreshTransactionHistory(using: addressReader,
                                                                               includeUnconfirmed: includeUnconfirmed)
            publish(.performedFullRefresh(utxoRefresh, historyChangeSet))
        } catch {
            await publishFailure(address: address, error: error)
        }
    }
}
