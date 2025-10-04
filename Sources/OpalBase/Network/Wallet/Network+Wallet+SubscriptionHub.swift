// Network+Wallet+SubscriptionHub.swift

import Foundation

extension Network.Wallet {
    public actor SubscriptionHub: SubscriptionService {
        public struct Notification: Sendable {
            public struct Event: Sendable {
                public let address: Address
                public let status: String?
                public let isReplay: Bool
                public let sequence: UInt64
            }
            
            public let address: Address
            public let notifications: [Event]
            public let enqueuedAt: ContinuousClock.Instant
            public let flushedAt: ContinuousClock.Instant
            
            public var latency: Duration { enqueuedAt.duration(to: flushedAt) }
        }
        
        public struct Stream: Sendable {
            public let id: UUID
            public let notifications: AsyncThrowingStream<Notification.Event, Swift.Error>
        }
        
        public struct Configuration: Sendable, Hashable {
            public struct SLO: Sendable, Hashable {
                public var targetFanOutLatency: Duration
                public var maxFanOutLatency: Duration
                public var minimumThroughputPerSecond: Double
                
                public init(targetFanOutLatency: Duration,
                            maxFanOutLatency: Duration,
                            minimumThroughputPerSecond: Double) {
                    self.targetFanOutLatency = targetFanOutLatency
                    self.maxFanOutLatency = maxFanOutLatency
                    self.minimumThroughputPerSecond = minimumThroughputPerSecond
                }
            }
            
            public var debounceInterval: Duration
            public var maxDebounceInterval: Duration
            public var maxBatchSize: Int
            public var slo: SLO
            
            public init(debounceInterval: Duration,
                        maxDebounceInterval: Duration,
                        maxBatchSize: Int,
                        slo: SLO) {
                self.debounceInterval = debounceInterval
                self.maxDebounceInterval = maxDebounceInterval
                self.maxBatchSize = maxBatchSize
                self.slo = slo
            }
            
            public static let standard = Configuration(
                debounceInterval: .milliseconds(35),
                maxDebounceInterval: .milliseconds(125),
                maxBatchSize: 16,
                slo: .init(
                    targetFanOutLatency: .milliseconds(75),
                    maxFanOutLatency: .milliseconds(150),
                    minimumThroughputPerSecond: 20
                )
            )
        }
        
        public protocol Persistence: Sendable {
            func loadState(for address: Address) async throws -> PersistenceState?
            func persist(_ state: PersistenceState) async throws
            func deactivate(address: Address, lastStatus: String?) async throws
        }
        
        public struct PersistenceState: Sendable, Hashable {
            public var address: Address
            public var isActive: Bool
            public var lastStatus: String?
            
            public init(address: Address, isActive: Bool, lastStatus: String?) {
                self.address = address
                self.isActive = isActive
                self.lastStatus = lastStatus
            }
        }
        
        public protocol ReplayAdapter: Sendable {
            func replay(for address: Address, lastStatus: String?) -> AsyncThrowingStream<Notification.Event, Swift.Error>
        }
        
        struct StorageBackfillAdapter: Persistence, ReplayAdapter, Sendable {
            let repository: Storage.Repository.Subscriptions
            
            init(repository: Storage.Repository.Subscriptions) {
                self.repository = repository
            }
            
            func loadState(for address: Address) async throws -> PersistenceState? {
                guard let row = try await repository.byAddress(address.string) else { return nil }
                return PersistenceState(address: address, isActive: row.isActive, lastStatus: row.lastStatus)
            }
            
            func persist(_ state: PersistenceState) async throws {
                try await repository.upsert(address: state.address.string,
                                            isActive: state.isActive,
                                            lastStatus: state.lastStatus)
            }
            
            func deactivate(address: Address, lastStatus: String?) async throws {
                try await repository.upsert(address: address.string,
                                            isActive: false,
                                            lastStatus: lastStatus)
            }
            
            func replay(for address: Address, lastStatus: String?) -> AsyncThrowingStream<Notification.Event, Swift.Error> {
                AsyncThrowingStream { continuation in
                    Task {
                        do {
                            let status: String?
                            if let lastStatus {
                                status = lastStatus
                            } else {
                                status = try await repository.byAddress(address.string)?.lastStatus
                            }
                            if let status {
                                continuation.yield(
                                    Notification.Event(address: address, status: status, isReplay: true, sequence: 0)
                                )
                            }
                            continuation.finish()
                        } catch {
                            continuation.finish(throwing: error)
                        }
                    }
                }
            }
        }
        
        public enum Error: Swift.Error, Sendable {
            case consumerNotFound(UUID)
            case storageFailure(Address, Swift.Error)
            case subscriptionFailed(Address, Swift.Error)
        }
        
        private struct SubscriptionState {
            var consumers: Set<UUID> = .init()
            var lastStatus: String?
            var lastSequence: UInt64 = 0
            var task: Task<Void, Never>?
            var cancel: (@Sendable () async -> Void)?
            var pending: [QueuedNotification] = .init()
            var flushTask: Task<Void, Never>?
            var lastEnqueue: ContinuousClock.Instant?
        }
        
        private struct QueuedNotification: Sendable {
            let status: String?
            let isReplay: Bool
            let enqueuedAt: ContinuousClock.Instant
        }
        
        private var consumers: [UUID: AsyncThrowingStream<Notification.Event, Swift.Error>.Continuation] = .init()
        private var consumerAddresses: [UUID: Set<Address>] = .init()
        private var subscriptions: [Address: SubscriptionState] = .init()
        private let configuration: Configuration
        private let persistence: (any Persistence)?
        private let replayAdapter: (any ReplayAdapter)?
        private let telemetry: Telemetry
        private let clock = ContinuousClock()
        
        public init(configuration: Configuration = .standard,
                    persistence: (any Persistence)? = nil,
                    replay: (any ReplayAdapter)? = nil,
                    telemetry: Telemetry = .shared) {
            self.configuration = configuration
            self.persistence = persistence
            self.replayAdapter = replay
            self.telemetry = telemetry
        }
        
        public init(configuration: Configuration = .standard,
                    repository: Storage.Repository.Subscriptions?) {
            if let repository {
                let adapter = StorageBackfillAdapter(repository: repository)
                self.init(configuration: configuration, persistence: adapter, replay: adapter)
            } else {
                self.init(configuration: configuration, persistence: nil, replay: nil)
            }
        }
        
        public func makeStream(for addresses: [Address],
                               using node: any Network.Wallet.Node,
                               consumerID: UUID) async throws -> Stream {
            let unique = Set(addresses)
            let stream = AsyncThrowingStream<Notification.Event, Swift.Error>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                Task {
                    await self.register(consumerID: consumerID,
                                        addresses: unique,
                                        node: node,
                                        continuation: continuation)
                }
                continuation.onTermination = { _ in
                    Task { await self.unregister(consumerID: consumerID) }
                }
            }
            
            return Stream(id: consumerID, notifications: stream)
        }
        
        public func add(addresses: [Address],
                        for consumerID: UUID,
                        using node: any Network.Wallet.Node) async throws {
            let unique = Set(addresses)
            guard !unique.isEmpty else { return }
            guard consumers[consumerID] != nil else { throw Error.consumerNotFound(consumerID) }
            consumerAddresses[consumerID, default: .init()].formUnion(unique)
            
            for address in unique {
                try await attach(consumerID: consumerID,
                                 address: address,
                                 node: node)
            }
        }
        
        public func remove(consumerID: UUID) async {
            await unregister(consumerID: consumerID)
        }
    }
}

private extension Network.Wallet.SubscriptionHub {
    func seconds(from duration: Duration) -> Double {
        let components = duration.components
        let attosecondsPerSecond = 1_000_000_000_000_000_000.0
        return Double(components.seconds) + Double(components.attoseconds) / attosecondsPerSecond
    }
    
    func milliseconds(from duration: Duration) -> Double {
        seconds(from: duration) * 1_000
    }
}

extension Network.Wallet.SubscriptionHub {
    func register(consumerID: UUID,
                  addresses: Set<Address>,
                  node: any Network.Wallet.Node,
                  continuation: AsyncThrowingStream<Notification.Event, Swift.Error>.Continuation) async {
        consumers[consumerID] = continuation
        consumerAddresses[consumerID, default: .init()].formUnion(addresses)
        
        for address in addresses {
            do {
                try await attach(consumerID: consumerID,
                                 address: address,
                                 node: node)
            } catch {
                continuation.finish(throwing: error)
                await unregister(consumerID: consumerID)
                break
            }
        }
    }
    
    func unregister(consumerID: UUID) async {
        guard let addresses = consumerAddresses.removeValue(forKey: consumerID) else { return }
        consumers.removeValue(forKey: consumerID)?.finish()
        
        for address in addresses {
            guard var state = subscriptions[address] else { continue }
            state.consumers.remove(consumerID)
            subscriptions[address] = state
            if state.consumers.isEmpty {
                await tearDown(address: address)
            }
        }
    }
    
    func attach(consumerID: UUID,
                address: Address,
                node: any Network.Wallet.Node) async throws {
        var state = subscriptions[address] ?? SubscriptionState()
        state.consumers.insert(consumerID)
        subscriptions[address] = state
        
        if let continuation = consumers[consumerID] {
            try await deliverReplay(for: address, to: continuation)
            guard isConsumerActive(consumerID: consumerID, address: address) else {
                await removeInactiveConsumer(consumerID, address: address)
                return
            }
        }
        
        guard isConsumerActive(consumerID: consumerID, address: address) else {
            await removeInactiveConsumer(consumerID, address: address)
            return
        }
        
        try await startStreamingIfNeeded(for: address, using: node)
    }
    
    func detach(consumerID: UUID, address: Address) async {
        guard var state = subscriptions[address] else { return }
        state.consumers.remove(consumerID)
        subscriptions[address] = state
        if state.consumers.isEmpty {
            await tearDown(address: address)
        }
    }
    
    func startStreamingIfNeeded(for address: Address,
                                using node: any Network.Wallet.Node) async throws {
        var state = subscriptions[address] ?? SubscriptionState()
        guard state.task == nil else { return }
        guard !state.consumers.isEmpty else { return }
        
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let subscription = try await node.subscribe(to: address)
                if let failure = await self.recordInitialStatus(subscription.initialStatus,
                                                                for: address,
                                                                cancel: subscription.cancel) {
                    await self.finishSubscription(for: address, error: failure)
                    return
                }
                
                for try await notification in subscription.updates {
                    await self.handle(notification: notification, for: address)
                }
                await self.finishSubscription(for: address, error: nil)
            } catch {
                await self.finishSubscription(for: address, error: error)
            }
        }
        
        state.task = task
        subscriptions[address] = state
    }
    
    func recordInitialStatus(_ status: String,
                             for address: Address,
                             cancel: @escaping @Sendable () async -> Void) async -> Swift.Error? {
        var state = subscriptions[address] ?? SubscriptionState()
        state.cancel = cancel
        subscriptions[address] = state
        
        await enqueue(status: status, isReplay: false, for: address, bypassDebounce: true)
        
        return nil
    }
    
    func handle(notification: Network.Wallet.SubscriptionStream.Notification,
                for address: Address) async {
        await enqueue(status: notification.status, isReplay: false, for: address, bypassDebounce: false)
    }
    
    func finishSubscription(for address: Address, error: Swift.Error?) async {
        guard var state = subscriptions[address] else { return }
        state.task?.cancel()
        state.task = nil
        state.flushTask?.cancel()
        state.flushTask = nil
        if let cancel = state.cancel { await cancel() }
        state.cancel = nil
        subscriptions[address] = state
        
        if let error {
            let wrapped = Error.subscriptionFailed(address, error)
            for consumerID in state.consumers {
                consumers[consumerID]?.finish(throwing: wrapped)
                consumerAddresses[consumerID]?.remove(address)
            }
            await persistInactive(address: address, lastStatus: state.lastStatus)
            subscriptions[address] = nil
            return
        }
        
        if state.consumers.isEmpty {
            await tearDown(address: address)
        } else {
            subscriptions[address] = state
        }
    }
    
    func tearDown(address: Address) async {
        guard var state = subscriptions[address] else { return }
        state.task?.cancel()
        state.task = nil
        state.flushTask?.cancel()
        state.flushTask = nil
        if let cancel = state.cancel { await cancel() }
        state.cancel = nil
        subscriptions[address] = nil
        await persistInactive(address: address, lastStatus: state.lastStatus)
    }
    
    func deliverReplay(for address: Address,
                       to continuation: AsyncThrowingStream<Notification.Event, Swift.Error>.Continuation) async throws {
        var state = subscriptions[address] ?? SubscriptionState()
        if state.lastStatus == nil, let persistence {
            do {
                if let stored = try await persistence.loadState(for: address) {
                    state.lastStatus = stored.lastStatus
                }
            } catch {
                throw Error.storageFailure(address, error)
            }
        }
        
        subscriptions[address] = state
        
        if let adapter = replayAdapter {
            let stream = adapter.replay(for: address, lastStatus: state.lastStatus)
            do {
                for try await replay in stream {
                    await enqueue(status: replay.status, isReplay: true, for: address, bypassDebounce: true)
                }
            } catch {
                throw Error.storageFailure(address, error)
            }
            await flushQueue(for: address, reason: "replay")
        } else if let status = state.lastStatus {
            var refreshed = subscriptions[address] ?? SubscriptionState()
            refreshed.lastSequence += 1
            refreshed.lastStatus = status
            subscriptions[address] = refreshed
            continuation.yield(
                .init(address: address, status: status, isReplay: true, sequence: refreshed.lastSequence)
            )
        }
    }
    
    func isConsumerActive(consumerID: UUID, address: Address) -> Bool {
        guard consumers[consumerID] != nil else { return false }
        guard let addresses = consumerAddresses[consumerID],
              addresses.contains(address)
        else { return false }
        guard let state = subscriptions[address],
              state.consumers.contains(consumerID)
        else { return false }
        return true
    }
    
    func removeInactiveConsumer(_ consumerID: UUID, address: Address) async {
        await detach(consumerID: consumerID, address: address)
    }
}

private extension Network.Wallet.SubscriptionHub {
    func enqueue(status: String?,
                 isReplay: Bool,
                 for address: Address,
                 bypassDebounce: Bool) async {
        var state = subscriptions[address] ?? SubscriptionState()
        let now = clock.now
        let payload = QueuedNotification(status: status, isReplay: isReplay, enqueuedAt: now)
        
        if let lastIndex = state.pending.indices.last,
           state.pending[lastIndex].status == payload.status,
           state.pending[lastIndex].enqueuedAt.duration(to: now) <= configuration.maxDebounceInterval {
            state.pending[lastIndex] = payload
        } else {
            state.pending.append(payload)
        }
        
        state.lastEnqueue = now
        subscriptions[address] = state
        
        if state.pending.count >= configuration.maxBatchSize || bypassDebounce {
            await flushQueue(for: address, reason: bypassDebounce ? "bypass" : "capacity")
            return
        }
        
        scheduleFlush(for: address)
    }
    
    func scheduleFlush(for address: Address) {
        guard var state = subscriptions[address], !state.pending.isEmpty else { return }
        state.flushTask?.cancel()
        let now = clock.now
        let lastEnqueue = state.lastEnqueue ?? now
        let debounceTarget = now + configuration.debounceInterval
        let maxTarget = lastEnqueue + configuration.maxDebounceInterval
        let target = debounceTarget < maxTarget ? debounceTarget : maxTarget
        
        state.flushTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(until: target, tolerance: .milliseconds(5))
            } catch { }
            await self.flushQueue(for: address, reason: "debounce")
        }
        
        subscriptions[address] = state
    }
    
    func flushQueue(for address: Address, reason: String) async {
        guard var state = subscriptions[address], !state.pending.isEmpty else { return }
        let now = clock.now
        let firstEnqueue = state.pending.first?.enqueuedAt ?? now
        var notifications: [Notification.Event] = .init()
        var sequence = state.lastSequence
        
        for entry in state.pending {
            sequence &+= 1
            notifications.append(
                Notification.Event(address: address,
                                   status: entry.status,
                                   isReplay: entry.isReplay,
                                   sequence: sequence)
            )
            state.lastStatus = entry.status
        }
        
        state.pending.removeAll(keepingCapacity: true)
        state.flushTask?.cancel()
        state.flushTask = nil
        state.lastSequence = sequence
        subscriptions[address] = state
        
        guard !notifications.isEmpty else { return }
        
        var awaitedOperations = 0
        
        if let persistence {
            awaitedOperations += 1
            do {
                try await persistence.persist(
                    .init(address: address, isActive: true, lastStatus: notifications.last?.status)
                )
            } catch {
                await finishSubscription(for: address, error: Error.storageFailure(address, error))
                return
            }
        }
        
        await fanOut(
            Notification(address: address,
                         notifications: notifications,
                         enqueuedAt: firstEnqueue,
                         flushedAt: now)
        )
        
        await emitTelemetry(for: address,
                            notifications: notifications,
                            firstEnqueue: firstEnqueue,
                            flushedAt: now,
                            reason: reason,
                            awaitedOperations: awaitedOperations)
    }
    
    func fanOut(_ batch: Notification) async {
        guard let state = subscriptions[batch.address] else { return }
        for consumerID in state.consumers {
            guard let continuation = consumers[consumerID] else { continue }
            for notification in batch.notifications {
                continuation.yield(notification)
            }
        }
    }
    
    func persistInactive(address: Address, lastStatus: String?) async {
        guard let persistence else { return }
        do {
            try await persistence.deactivate(address: address, lastStatus: lastStatus)
        } catch {
            Task { [telemetry] in
                await telemetry.record(
                    name: "network.wallet.subscription.persistence_failure",
                    category: .storage,
                    message: "Failed to deactivate subscription",
                    metadata: [
                        "subscription.address": .string(address.string)
                    ],
                    metrics: [:],
                    sensitiveKeys: ["subscription.address"]
                )
            }
        }
    }
    
    func emitTelemetry(for address: Address,
                       notifications: [Notification.Event],
                       firstEnqueue: ContinuousClock.Instant,
                       flushedAt: ContinuousClock.Instant,
                       reason: String,
                       awaitedOperations: Int) async {
        guard !notifications.isEmpty else { return }
        let latency = firstEnqueue.duration(to: flushedAt)
        let count = Double(notifications.count)
        let throughput = count / max(seconds(from: latency), 0.001)
        let ratio = count == 0 ? 0 : Double(awaitedOperations) / count
        
        let metadata: Telemetry.Metadata = [
            "subscription.address": .string(address.string),
            "subscription.flush_reason": .string(reason)
        ]
        
        let slo = configuration.slo
        let metrics: [String: Double] = [
            "subscription.batch.count": count,
            "subscription.batch.latency_ms": milliseconds(from: latency),
            "subscription.batch.throughput": throughput,
            "subscription.await_ratio": ratio,
            "subscription.await_ratio.target": 1.5,
            "subscription.slo.target_latency_ms": milliseconds(from: slo.targetFanOutLatency),
            "subscription.slo.max_latency_ms": milliseconds(from: slo.maxFanOutLatency),
            "subscription.slo.min_throughput_per_s": slo.minimumThroughputPerSecond
        ]
        
        Task { [telemetry] in
            await telemetry.record(
                name: "network.wallet.subscription.fanout",
                category: .network,
                message: "Flushed subscription batch",
                metadata: metadata,
                metrics: metrics,
                sensitiveKeys: ["subscription.address"]
            )
        }
    }
}
