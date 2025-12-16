// Wallet+FulcrumAddress+Monitor.swift

import Foundation

extension Wallet.FulcrumAddress {
    public actor Monitor {
        public struct Failure: Sendable {
            public let address: Address?
            public let message: String
            
            public init(address: Address?, message: String) {
                self.address = address
                self.message = message
            }
        }
        
        public enum Event: Sendable {
            case addressMonitored(Address)
            case utxosUpdated(address: Address, balance: Satoshi, utxos: [Transaction.Output.Unspent])
            case historyChanged(Transaction.History.ChangeSet)
            case confirmationsChanged(Transaction.History.ChangeSet)
            case performedFullRefresh(Address.Book.UTXORefresh, Transaction.History.ChangeSet)
            case encounteredFailure(Failure)
        }
        
        let account: Account
        let addressReader: Network.AddressReadable
        let blockHeaderReader: Network.BlockHeaderReadable
        let transactionHandler: Network.TransactionConfirming
        let includeUnconfirmed: Bool
        let retryDelay: Duration
        
        var addressSubscriptions: [Address: Task<Void, Never>]
        var newEntryTask: Task<Void, Never>?
        var headerTask: Task<Void, Never>?
        private var eventContinuations: [UUID: AsyncStream<Event>.Continuation]
        private var isRunning: Bool
        
        public init(account: Account,
                    addressReader: Network.AddressReadable,
                    blockHeaderReader: Network.BlockHeaderReadable,
                    transactionHandler: Network.TransactionConfirming,
                    includeUnconfirmed: Bool = true,
                    retryDelay: Duration = .seconds(2)) {
            self.account = account
            self.addressReader = addressReader
            self.blockHeaderReader = blockHeaderReader
            self.transactionHandler = transactionHandler
            self.includeUnconfirmed = includeUnconfirmed
            self.retryDelay = retryDelay
            self.addressSubscriptions = .init()
            self.eventContinuations = .init()
            self.isRunning = false
        }
        
        deinit {
            for task in addressSubscriptions.values { task.cancel() }
            newEntryTask?.cancel()
            headerTask?.cancel()
        }
        
        public func start() async {
            guard !isRunning else { return }
            isRunning = true
            
            let existingEntries = await account.listTrackedEntries()
            for entry in existingEntries {
                registerEntry(entry)
            }
            
            await startEntryObservation()
            await startHeaderSubscription()
        }
        
        public func stop() {
            guard isRunning else { return }
            isRunning = false
            cancelSubscriptions()
            cancelEntryTask()
            cancelHeaderTask()
            finishContinuations()
        }
        
        public func observeEvents() -> AsyncStream<Event> {
            AsyncStream { continuation in
                let identifier = UUID()
                Task { storeContinuation(continuation, identifier: identifier) }
                continuation.onTermination = { _ in
                    Task { await self.removeContinuation(withIdentifier: identifier) }
                }
            }
        }
        
        private func storeContinuation(_ continuation: AsyncStream<Event>.Continuation,
                                       identifier: UUID) {
            eventContinuations[identifier] = continuation
        }
        
        private func removeContinuation(withIdentifier identifier: UUID) {
            eventContinuations.removeValue(forKey: identifier)
        }
        
        func publishFailure(address: Address?, error: Swift.Error) async {
            let message = String(describing: error)
            publish(.encounteredFailure(.init(address: address, message: message)))
        }
        
        private func cancelSubscriptions() {
            for subscription in addressSubscriptions.values {
                subscription.cancel()
            }
            addressSubscriptions.removeAll()
        }
        
        private func cancelEntryTask() {
            newEntryTask?.cancel()
            newEntryTask = nil
        }
        
        private func cancelHeaderTask() {
            headerTask?.cancel()
            headerTask = nil
        }
        
        private func finishContinuations() {
            for continuation in eventContinuations.values {
                continuation.finish()
            }
            eventContinuations.removeAll()
        }
        
        func publish(_ event: Event) {
            guard !eventContinuations.isEmpty else { return }
            for continuation in eventContinuations.values {
                continuation.yield(event)
            }
        }
    }
}
