// WalletActor+FulcrumAddressActor+MonitorActor.swift

import Foundation

extension WalletActor.FulcrumAddressActor {
    public actor MonitorActor {
        public struct Failure: Sendable {
            public let address: AddressModel?
            public let message: String
            
            public init(address: AddressModel?, message: String) {
                self.address = address
                self.message = message
            }
        }
        
        public struct Termination: Sendable {
            public enum Reason: Sendable {
                case stopped
                case cancelled
            }
            
            public let reason: Reason
            
            public init(reason: Reason) {
                self.reason = reason
            }
        }
        
        public enum Event: Sendable {
            case addressTracked(AddressModel)
            case utxosChanged(AddressModel.BookActor.UTXOChangeSetModel)
            case historyChanged(TransactionModel.HistoryModel.ChangeSetModel)
            case confirmationsChanged(TransactionModel.HistoryModel.ChangeSetModel)
            case performedFullRefresh(AddressModel.BookActor.UTXORefreshModel, TransactionModel.HistoryModel.ChangeSetModel)
            case encounteredFailure(Failure)
            case terminated(Termination)
        }
        
        let account: AccountActor
        let addressReader: NetworkModel.AddressReadable
        let blockHeaderReader: NetworkModel.BlockHeaderReadable
        let transactionHandler: NetworkModel.TransactionConfirmationClient
        let transactionReader: NetworkModel.TransactionReadableClient?
        let shouldIncludeUnconfirmed: Bool
        let retryDelay: Duration
        
        var addressSubscriptions: [AddressModel: Task<Void, Never>]
        var newEntryTask: Task<Void, Never>?
        var headerTask: Task<Void, Never>?
        private var eventContinuations: [UUID: AsyncThrowingStream<Event, Swift.Error>.Continuation]
        private var isRunning: Bool
        
        public init(account: AccountActor,
                    addressReader: NetworkModel.AddressReadable,
                    blockHeaderReader: NetworkModel.BlockHeaderReadable,
                    transactionHandler: NetworkModel.TransactionConfirmationClient,
                    transactionReader: NetworkModel.TransactionReadableClient? = nil,
                    includeUnconfirmed: Bool = true,
                    retryDelay: Duration = .seconds(2)) {
            self.account = account
            self.addressReader = addressReader
            self.blockHeaderReader = blockHeaderReader
            self.transactionHandler = transactionHandler
            self.transactionReader = transactionReader
            self.shouldIncludeUnconfirmed = includeUnconfirmed
            self.retryDelay = retryDelay
            self.addressSubscriptions = .init()
            self.eventContinuations = .init()
            self.isRunning = false
        }
        
        deinit {
            Task { [weak weakSelf = self] in
                guard let monitor = weakSelf else { return }
                await monitor.performDeinitCleanup()
            }
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
        
        public func stop(reason: Termination.Reason = .stopped) {
            guard isRunning else { return }
            isRunning = false
            cancelSubscriptions()
            cancelEntryTask()
            cancelHeaderTask()
            publish(.terminated(.init(reason: reason)))
            finishContinuations()
        }
        
        public func makeEventStream(autoStart: Bool = true) -> AsyncThrowingStream<Event, Swift.Error> {
            AsyncThrowingStream { continuation in
                let identifier = UUID()
                Task { await storeContinuation(continuation, identifier: identifier, autoStart: autoStart) }
                continuation.onTermination = { termination in
                    Task { await self.removeContinuation(withIdentifier: identifier, termination: termination) }
                }
            }
        }
        
        private func storeContinuation(_ continuation: AsyncThrowingStream<Event, Swift.Error>.Continuation,
                                       identifier: UUID,
                                       autoStart: Bool) async {
            eventContinuations[identifier] = continuation
            
            guard autoStart else { return }
            await start()
        }
        
        private func removeContinuation(withIdentifier identifier: UUID,
                                        termination: AsyncThrowingStream<Event, Swift.Error>.Continuation.Termination?) async {
            eventContinuations.removeValue(forKey: identifier)
            
            guard eventContinuations.isEmpty else { return }
            switch termination {
            case .cancelled?:
                stop(reason: .cancelled)
            default:
                stop()
            }
        }
        
        func publishFailure(address: AddressModel?, error: Swift.Error) async {
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
        
        private func performDeinitCleanup() {
            cancelSubscriptions()
            cancelEntryTask()
            cancelHeaderTask()
            finishContinuations()
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
