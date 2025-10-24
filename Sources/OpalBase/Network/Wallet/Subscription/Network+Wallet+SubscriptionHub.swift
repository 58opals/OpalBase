// Network+Wallet+SubscriptionHub.swift

import Foundation

extension Network.Wallet {
    public actor SubscriptionHub {
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
        
        public struct Persistence: Sendable {
            public enum Error: Swift.Error, Sendable, Equatable {
                case repository(String)
            }
            
            public typealias Loader = @Sendable (Address) async throws -> PersistenceState?
            public typealias Writer = @Sendable (PersistenceState) async throws -> Void
            public typealias Deactivator = @Sendable (Address, String?) async throws -> Void
            
            private let loader: Loader
            private let writer: Writer
            private let deactivator: Deactivator
            
            public init(loader: @escaping Loader,
                        writer: @escaping Writer,
                        deactivator: @escaping Deactivator) {
                self.loader = loader
                self.writer = writer
                self.deactivator = deactivator
            }
            
            func load(address: Address) async throws -> PersistenceState? {
                try await loader(address)
            }
            
            func persist(_ state: PersistenceState) async throws {
                try await writer(state)
            }
            
            func deactivate(address: Address, lastStatus: String?) async throws {
                try await deactivator(address, lastStatus)
            }
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
        
        public struct Replay: Sendable {
            public typealias Factory = @Sendable (Address, String?) -> AsyncThrowingStream<Notification.Event, Swift.Error>
            
            private let factory: Factory
            
            public init(factory: @escaping Factory) {
                self.factory = factory
            }
            
            func stream(for address: Address, lastStatus: String?) -> AsyncThrowingStream<Notification.Event, Swift.Error> {
                factory(address, lastStatus)
            }
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
        let persistence: Persistence?
        let replay: Replay?
        let telemetry: Telemetry
        let clock = ContinuousClock()
        
        public init(configuration: Configuration = .standard,
                    persistence: Persistence? = nil,
                    replay: Replay? = nil,
                    telemetry: Telemetry = .shared) {
            self.configuration = configuration
            self.persistence = persistence
            self.replay = replay
            self.telemetry = telemetry
        }
        
        public init(configuration: Configuration = .standard,
                    repository: Storage.Repository.Subscriptions?) {
            if let repository {
                self.init(configuration: configuration,
                          persistence: .storage(repository: repository),
                          replay: .storage(repository: repository))
            } else {
                self.init(configuration: configuration, persistence: nil, replay: nil)
            }
        }
        
        public func makeStream(for addresses: [Address],
                               using node: Network.Wallet.Node,
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
                        using node: Network.Wallet.Node) async throws {
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
