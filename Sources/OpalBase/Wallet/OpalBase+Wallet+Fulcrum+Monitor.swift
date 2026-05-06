// OpalBase+Wallet+Fulcrum+Monitor.swift

import Foundation

extension _OpalBase.Wallet.Fulcrum {
    public actor Monitor {
        public struct Failure: Sendable {
            public let address: OpalBase.Address?
            public let message: String

            public init(address: OpalBase.Address?, message: String) {
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
            case addressTracked(OpalBase.Address)
            case utxosChanged(OpalBase.Account.UTXOChangeSet)
            case historyChanged(OpalBase.Transaction.History.ChangeSet)
            case confirmationsChanged(OpalBase.Transaction.History.ChangeSet)
            case performedFullRefresh(OpalBase.Account.UTXORefresh, OpalBase.Transaction.History.ChangeSet)
            case encounteredFailure(Failure)
            case terminated(Termination)
        }

        let dependencies: WorkerDependencies
        let eventHub: EventHub
        var addressSubscriptions: [OpalBase.Address: Task<Void, Never>]
        var newEntryTask: Task<Void, Never>?
        var headerTask: Task<Void, Never>?
        var activeEventStreamIdentifiers: Set<UUID>
        var isRunning: Bool
        var isFinished: Bool
        var isManagedByEventStreams: Bool

        public init(account: OpalBase.Account,
                    addressReader: OpalBase.Network.AddressReader,
                    blockHeaderReader: OpalBase.Network.BlockHeaderReader,
                    transactionClient: OpalBase.Network.TransactionClient,
                    transactionReader: OpalBase.Network.TransactionReader? = nil,
                    includeUnconfirmed: Bool = true,
                    retryDelay: Duration = .seconds(2)) {
            let eventHub = EventHub()
            self.eventHub = eventHub
            self.dependencies = .init(
                account: account,
                addressReader: addressReader,
                blockHeaderReader: blockHeaderReader,
                transactionClient: transactionClient,
                transactionReader: transactionReader,
                shouldIncludeUnconfirmed: includeUnconfirmed,
                retryDelay: retryDelay,
                eventHub: eventHub
            )
            self.addressSubscriptions = .init()
            self.activeEventStreamIdentifiers = .init()
            self.isRunning = false
            self.isFinished = false
            self.isManagedByEventStreams = false
        }

        deinit {
            for subscription in addressSubscriptions.values {
                subscription.cancel()
            }
            newEntryTask?.cancel()
            headerTask?.cancel()
            let eventHub = eventHub
            Task {
                await eventHub.finishAll()
            }
        }

        public func start() async {
            await start(shouldStopWhenStreamsEnd: false)
        }

        private func start(shouldStopWhenStreamsEnd: Bool) async {
            guard !isFinished else { return }
            if isRunning {
                if shouldStopWhenStreamsEnd == false {
                    isManagedByEventStreams = false
                }
                return
            }
            isRunning = true
            isManagedByEventStreams = shouldStopWhenStreamsEnd

            let existingEntries = await dependencies.account.listTrackedEntries()
            for entry in existingEntries {
                await registerEntry(entry)
            }

            await startEntryObservation()
            await startHeaderSubscription()
        }

        public func stop(reason: Termination.Reason = .stopped) async {
            await tearDown(reason: reason, shouldPublishTermination: true)
        }

        public func makeEventStream(autoStart: Bool = true) async -> AsyncThrowingStream<Event, Swift.Error> {
            guard !isFinished else {
                return AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }

            let identifier = UUID()
            activeEventStreamIdentifiers.insert(identifier)

            return await eventHub.makeStream(
                identifier: identifier,
                autoStart: autoStart,
                monitor: self
            )
        }

        fileprivate func startIfStreamIsStillActive(identifier: UUID) async {
            guard !isFinished,
                  activeEventStreamIdentifiers.contains(identifier) else {
                return
            }

            await start(shouldStopWhenStreamsEnd: true)
        }

        fileprivate func handleEventStreamTermination(
            identifier: UUID,
            termination: AsyncThrowingStream<Event, Swift.Error>.Continuation.Termination
        ) async {
            activeEventStreamIdentifiers.remove(identifier)
            await eventHub.removeContinuation(withIdentifier: identifier)

            guard activeEventStreamIdentifiers.isEmpty else {
                return
            }
            guard isManagedByEventStreams else {
                return
            }

            switch termination {
            case .cancelled:
                await tearDown(reason: .cancelled, shouldPublishTermination: false)
            default:
                await tearDown(reason: .stopped, shouldPublishTermination: false)
            }
        }

        private func tearDown(
            reason: Termination.Reason,
            shouldPublishTermination: Bool
        ) async {
            guard !isFinished else { return }

            isFinished = true
            isRunning = false
            isManagedByEventStreams = false
            activeEventStreamIdentifiers.removeAll()
            cancelSubscriptions()
            cancelEntryTask()
            cancelHeaderTask()

            if shouldPublishTermination {
                await eventHub.publish(.terminated(.init(reason: reason)))
            }
            await eventHub.finishAll()
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
    }
}

extension _OpalBase.Wallet.Fulcrum.Monitor {
    struct WorkerDependencies: Sendable {
        let account: OpalBase.Account
        let addressReader: OpalBase.Network.AddressReader
        let blockHeaderReader: OpalBase.Network.BlockHeaderReader
        let transactionClient: OpalBase.Network.TransactionClient
        let transactionReader: OpalBase.Network.TransactionReader?
        let shouldIncludeUnconfirmed: Bool
        let retryDelay: Duration
        let eventHub: EventHub
    }
}

extension _OpalBase.Wallet.Fulcrum.Monitor {
    actor EventHub {
        typealias Event = OpalBase.Wallet.Fulcrum.Monitor.Event
        typealias Continuation = AsyncThrowingStream<Event, Swift.Error>.Continuation

        private var continuations: [UUID: Continuation] = .init()

        func makeStream(
            identifier: UUID,
            autoStart: Bool,
            monitor: OpalBase.Wallet.Fulcrum.Monitor
        ) -> AsyncThrowingStream<Event, Swift.Error> {
            AsyncThrowingStream { continuation in
                continuations[identifier] = continuation

                if autoStart {
                    Task(priority: .userInitiated) {
                        await monitor.startIfStreamIsStillActive(identifier: identifier)
                    }
                }

                continuation.onTermination = { [monitor] termination in
                    Task {
                        await monitor.handleEventStreamTermination(
                            identifier: identifier,
                            termination: termination
                        )
                    }
                }
            }
        }

        func removeContinuation(withIdentifier identifier: UUID) {
            continuations.removeValue(forKey: identifier)
        }

        func publish(_ event: Event) {
            for continuation in continuations.values {
                continuation.yield(event)
            }
        }

        func finishAll() {
            let activeContinuations = Array(continuations.values)
            continuations.removeAll()
            for continuation in activeContinuations {
                continuation.finish()
            }
        }
    }
}
