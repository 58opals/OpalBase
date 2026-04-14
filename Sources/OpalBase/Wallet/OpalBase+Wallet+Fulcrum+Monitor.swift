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
            case utxosChanged(OpalBase.Address.Book.UTXOChangeSet)
            case historyChanged(OpalBase.Transaction.History.ChangeSet)
            case confirmationsChanged(OpalBase.Transaction.History.ChangeSet)
            case performedFullRefresh(OpalBase.Address.Book.UTXORefresh, OpalBase.Transaction.History.ChangeSet)
            case encounteredFailure(Failure)
            case terminated(Termination)
        }

        let dependencies: WorkerDependencies
        let relay: EventRelay
        var addressSubscriptions: [OpalBase.Address: Task<Void, Never>]
        var newEntryTask: Task<Void, Never>?
        var headerTask: Task<Void, Never>?
        var activeEventStreamIdentifiers: Set<UUID>
        var isRunning: Bool
        var isFinished: Bool

        public init(account: OpalBase.Account,
                    addressReader: OpalBase.Network.AddressReader,
                    blockHeaderReader: OpalBase.Network.BlockHeaderReader,
                    transactionClient: OpalBase.Network.TransactionClient,
                    transactionReader: OpalBase.Network.TransactionReader? = nil,
                    includeUnconfirmed: Bool = true,
                    retryDelay: Duration = .seconds(2)) {
            let relay = EventRelay()
            self.relay = relay
            self.dependencies = .init(
                account: account,
                addressReader: addressReader,
                blockHeaderReader: blockHeaderReader,
                transactionClient: transactionClient,
                transactionReader: transactionReader,
                shouldIncludeUnconfirmed: includeUnconfirmed,
                retryDelay: retryDelay,
                relay: relay
            )
            self.addressSubscriptions = .init()
            self.activeEventStreamIdentifiers = .init()
            self.isRunning = false
            self.isFinished = false
        }

        deinit {
            for subscription in addressSubscriptions.values {
                subscription.cancel()
            }
            newEntryTask?.cancel()
            headerTask?.cancel()
            relay.finishAll()
        }

        public func start() async {
            guard !isFinished, !isRunning else { return }
            isRunning = true

            let existingEntries = await dependencies.account.listTrackedEntries()
            for entry in existingEntries {
                registerEntry(entry)
            }

            await startEntryObservation()
            await startHeaderSubscription()
        }

        public func stop(reason: Termination.Reason = .stopped) {
            tearDown(reason: reason, shouldPublishTermination: true)
        }

        public func makeEventStream(autoStart: Bool = true) -> AsyncThrowingStream<Event, Swift.Error> {
            guard !isFinished else {
                return AsyncThrowingStream { continuation in
                    continuation.finish()
                }
            }

            let identifier = UUID()
            let relay = relay
            activeEventStreamIdentifiers.insert(identifier)
            let lifetime = EventStreamLifetime(monitor: self, identifier: identifier)

            return AsyncThrowingStream { continuation in
                _ = lifetime
                relay.storeContinuation(continuation, identifier: identifier)

                if autoStart {
                    Task.detached(priority: .userInitiated) { [lifetime] in
                        await lifetime.monitor.startIfStreamIsStillActive(identifier: lifetime.identifier)
                    }
                }

                continuation.onTermination = { [lifetime] termination in
                    Task.detached { [lifetime] in
                        await lifetime.monitor.handleEventStreamTermination(
                            identifier: lifetime.identifier,
                            termination: termination
                        )
                    }
                }
            }
        }

        private func startIfStreamIsStillActive(identifier: UUID) async {
            guard !isFinished,
                  activeEventStreamIdentifiers.contains(identifier) else {
                return
            }

            await start()
        }

        private func handleEventStreamTermination(
            identifier: UUID,
            termination: AsyncThrowingStream<Event, Swift.Error>.Continuation.Termination
        ) async {
            activeEventStreamIdentifiers.remove(identifier)
            _ = relay.removeContinuation(withIdentifier: identifier)

            guard activeEventStreamIdentifiers.isEmpty else {
                return
            }

            switch termination {
            case .cancelled:
                tearDown(reason: .cancelled, shouldPublishTermination: false)
            default:
                tearDown(reason: .stopped, shouldPublishTermination: false)
            }
        }

        private func tearDown(
            reason: Termination.Reason,
            shouldPublishTermination: Bool
        ) {
            guard !isFinished else { return }

            isFinished = true
            isRunning = false
            activeEventStreamIdentifiers.removeAll()
            cancelSubscriptions()
            cancelEntryTask()
            cancelHeaderTask()

            if shouldPublishTermination {
                relay.publish(.terminated(.init(reason: reason)))
            }
            relay.finishAll()
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
        let relay: EventRelay
    }
}

private final class EventStreamLifetime: @unchecked Sendable {
    let monitor: OpalBase.Wallet.Fulcrum.Monitor
    let identifier: UUID

    init(
        monitor: OpalBase.Wallet.Fulcrum.Monitor,
        identifier: UUID
    ) {
        self.monitor = monitor
        self.identifier = identifier
    }
}

final class EventRelay: @unchecked Sendable {
    typealias Event = OpalBase.Wallet.Fulcrum.Monitor.Event
    typealias Continuation = AsyncThrowingStream<Event, Swift.Error>.Continuation

    private let lock = NSLock()
    private var continuations: [UUID: Continuation] = .init()

    func storeContinuation(_ continuation: Continuation, identifier: UUID) {
        lock.lock()
        continuations[identifier] = continuation
        lock.unlock()
    }

    func removeContinuation(withIdentifier identifier: UUID) -> Bool {
        lock.lock()
        continuations.removeValue(forKey: identifier)
        let isEmpty = continuations.isEmpty
        lock.unlock()
        return isEmpty
    }

    func publish(_ event: Event) {
        let activeContinuations = snapshotContinuations()
        for continuation in activeContinuations {
            continuation.yield(event)
        }
    }

    func finishAll() {
        let activeContinuations = drainContinuations()
        for continuation in activeContinuations {
            continuation.finish()
        }
    }

    private func snapshotContinuations() -> [Continuation] {
        lock.lock()
        let activeContinuations = Array(continuations.values)
        lock.unlock()
        return activeContinuations
    }

    private func drainContinuations() -> [Continuation] {
        lock.lock()
        let activeContinuations = Array(continuations.values)
        continuations.removeAll()
        lock.unlock()
        return activeContinuations
    }
}
