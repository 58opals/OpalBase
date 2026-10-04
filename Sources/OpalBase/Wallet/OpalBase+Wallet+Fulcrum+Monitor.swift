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
        var connectionTask: Task<Void, Never>?
        let connectionRecoveryStates: AsyncStream<OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation>?
        let monitorsBlockHeaders: Bool
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
                    retryDelay: Duration = .seconds(2),
                    monitorsBlockHeaders: Bool = true,
                    connectionRecoveryStates: AsyncStream<OpalBase.Network.Fulcrum.Client.ConnectionRecoveryObservation>? = nil) {
            let eventHub = EventHub(tracksConnectionRecovery: connectionRecoveryStates != nil)
            self.eventHub = eventHub
            self.monitorsBlockHeaders = monitorsBlockHeaders
            self.connectionRecoveryStates = connectionRecoveryStates
            self.dependencies = .init(
                account: account,
                addressReader: addressReader,
                blockHeaderReader: blockHeaderReader,
                transactionClient: transactionClient,
                transactionReader: transactionReader,
                shouldIncludeUnconfirmed: includeUnconfirmed,
                retryDelay: Self.clampedRetryDelay(retryDelay),
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
            connectionTask?.cancel()
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

            await startEntryObservation()
            await startConnectionObservation()
            let existingEntries = await dependencies.account.listTrackedEntries()
            guard isRunning, !isFinished else { return }

            for entry in existingEntries {
                await registerEntry(entry)
                guard isRunning, !isFinished else { return }
            }

            await eventHub.establishScope()
            if monitorsBlockHeaders {
                await startHeaderSubscription()
            }
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

        func startIfStreamIsStillActive(identifier: UUID) async {
            guard !isFinished,
                  activeEventStreamIdentifiers.contains(identifier) else {
                return
            }

            await start(shouldStopWhenStreamsEnd: true)
        }

        func handleEventStreamTermination(
            identifier: UUID,
            reason: Termination.Reason
        ) async {
            activeEventStreamIdentifiers.remove(identifier)
            await eventHub.removeContinuation(withIdentifier: identifier)

            guard activeEventStreamIdentifiers.isEmpty else {
                return
            }
            guard isManagedByEventStreams else {
                return
            }

            switch reason {
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
            connectionTask?.cancel()
            connectionTask = nil

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

        private static func clampedRetryDelay(_ retryDelay: Duration) -> Duration {
            max(.milliseconds(1), retryDelay)
        }
    }
}

extension _OpalBase.Wallet.Fulcrum.Monitor {
    actor StartupGate {
        private var isComplete = false
        private var continuations: [CheckedContinuation<Void, Never>] = .init()

        func wait() async {
            if isComplete { return }

            await withCheckedContinuation { continuation in
                if isComplete {
                    continuation.resume()
                } else {
                    continuations.append(continuation)
                }
            }
        }

        func complete() {
            guard !isComplete else { return }

            isComplete = true
            let pendingContinuations = continuations
            continuations.removeAll()

            for continuation in pendingContinuations {
                continuation.resume()
            }
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
