// Network+Wallet+SubscriptionHub.swift

import Foundation

extension Network.Wallet {
    public actor SubscriptionHub: SubscriptionService {
        public struct Notification: Sendable {
            public struct Event: Sendable {
                public let address: Address
                public let status: String?
                public let replayFlag: Bool
                public let sequence: UInt64
            }
            
            public let address: Address
            public let events: [Event]
            public let enqueueInstant: ContinuousClock.Instant
            public let flushInstant: ContinuousClock.Instant
            
            public init(address: Address,
                        events: [Event],
                        enqueueInstant: ContinuousClock.Instant,
                        flushInstant: ContinuousClock.Instant) {
                self.address = address
                self.events = events
                self.enqueueInstant = enqueueInstant
                self.flushInstant = flushInstant
            }
            
            public var latencyDuration: Duration { enqueueInstant.duration(to: flushInstant) }
        }
        
        public struct Stream: Sendable {
            public let id: UUID
            public let eventStream: AsyncThrowingStream<Notification.Event, Swift.Error>
            
            public init(id: UUID,
                        eventStream: AsyncThrowingStream<Notification.Event, Swift.Error>) {
                self.id = id
                self.eventStream = eventStream
            }
        }
        
        public struct Configuration: Sendable, Hashable {
            public struct ServiceLevelObjective: Sendable, Hashable {
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
            public var serviceLevelObjective: ServiceLevelObjective
            
            public init(debounceInterval: Duration,
                        maxDebounceInterval: Duration,
                        maxBatchSize: Int,
                        serviceLevelObjective: ServiceLevelObjective) {
                self.debounceInterval = debounceInterval
                self.maxDebounceInterval = maxDebounceInterval
                self.maxBatchSize = maxBatchSize
                self.serviceLevelObjective = serviceLevelObjective
            }
            
            public static let standard = Configuration(
                debounceInterval: .milliseconds(35),
                maxDebounceInterval: .milliseconds(125),
                maxBatchSize: 16,
                serviceLevelObjective: .init(
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
            public var activationFlag: Bool
            public var lastStatus: String?
            
            public init(address: Address, activationFlag: Bool, lastStatus: String?) {
                self.address = address
                self.activationFlag = activationFlag
                self.lastStatus = lastStatus
            }
        }
        
        public protocol ReplayAdapter: Sendable {
            func replay(for address: Address, lastStatus: String?) -> AsyncThrowingStream<Notification.Event, Swift.Error>
        }
        
        public enum Error: Swift.Error, Sendable {
            case consumerNotFound(UUID)
            case storageFailure(Address, Swift.Error)
            case subscriptionFailed(Address, Swift.Error)
        }
        
        var consumerContinuations: [UUID: AsyncThrowingStream<Notification.Event, Swift.Error>.Continuation] = .init()
        var consumerAddressBook: [UUID: Set<Address>] = .init()
        var subscriptionStates: [Address: State] = .init()
        let configuration: Configuration
        let persistence: (any Persistence)?
        let replayAdapter: (any ReplayAdapter)?
        let telemetry: Telemetry
        let clock = ContinuousClock()
        
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
            let uniqueAddresses = Set(addresses)
            let stream = AsyncThrowingStream<Notification.Event, Swift.Error>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                Task {
                    await self.register(consumerID: consumerID,
                                        addresses: uniqueAddresses,
                                        node: node,
                                        continuation: continuation)
                }
                continuation.onTermination = { _ in
                    Task { await self.unregister(consumerID: consumerID) }
                }
            }
            
            return Stream(id: consumerID, eventStream: stream)
        }
        
        public func add(addresses: [Address],
                        for consumerID: UUID,
                        using node: any Network.Wallet.Node) async throws {
            let uniqueAddresses = Set(addresses)
            guard !uniqueAddresses.isEmpty else { return }
            guard consumerContinuations[consumerID] != nil else { throw Error.consumerNotFound(consumerID) }
            consumerAddressBook[consumerID, default: .init()].formUnion(uniqueAddresses)
            
            for address in uniqueAddresses {
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
