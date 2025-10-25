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
        
        public struct Dependencies: Sendable {
            public enum Error: Swift.Error, Sendable, Equatable {
                case repository(String)
            }
            
            public typealias PersistenceLoader = @Sendable (Address) async throws -> PersistenceState?
            public typealias PersistenceWriter = @Sendable (PersistenceState) async throws -> Void
            public typealias PersistenceDeactivator = @Sendable (Address, String?) async throws -> Void
            public typealias ReplayFactory = @Sendable (Address, String?) -> AsyncThrowingStream<Notification.Event, Swift.Error>
            
            private let loader: PersistenceLoader?
            private let writer: PersistenceWriter?
            private let deactivator: PersistenceDeactivator?
            private let replayFactory: ReplayFactory?
            
            public init(loader: PersistenceLoader? = nil,
                        writer: PersistenceWriter? = nil,
                        deactivator: PersistenceDeactivator? = nil,
                        replayFactory: ReplayFactory? = nil) {
                self.loader = loader
                self.writer = writer
                self.deactivator = deactivator
                self.replayFactory = replayFactory
            }
            
            public var hasPersistenceLoader: Bool { loader != nil }
            public var hasPersistenceWriter: Bool { writer != nil }
            public var hasPersistenceDeactivator: Bool { deactivator != nil }
            public var hasReplayFactory: Bool { replayFactory != nil }
            
            
            func load(address: Address) async throws -> PersistenceState? {
                guard let loader else { return nil }
                return try await loader(address)
            }
            
            func persist(_ state: PersistenceState) async throws {
                guard let writer else { return }
                try await writer(state)
            }
            
            func deactivate(address: Address, lastStatus: String?) async throws {
                guard let deactivator else { return }
                try await deactivator(address, lastStatus)
            }
            
            func replayStream(for address: Address,
                              lastStatus: String?) -> AsyncThrowingStream<Notification.Event, Swift.Error>? {
                guard let replayFactory else { return nil }
                return replayFactory(address, lastStatus)
            }
        }
        
        public enum Error: Swift.Error, Sendable {
            case consumerNotFound(UUID)
            case storageFailure(Address, Swift.Error)
            case subscriptionFailed(Address, Swift.Error)
        }
        
        struct AddressBook: Sendable {
            private var storage: [UUID: Set<Address>] = [:]
            
            mutating func union(_ addresses: Set<Address>, for consumerID: UUID) {
                storage[consumerID, default: .init()].formUnion(addresses)
            }
            
            mutating func removeAddresses(for consumerID: UUID) -> Set<Address>? {
                storage.removeValue(forKey: consumerID)
            }
            
            mutating func remove(_ address: Address, for consumerID: UUID) {
                guard var addresses = storage[consumerID] else { return }
                addresses.remove(address)
                if addresses.isEmpty {
                    storage.removeValue(forKey: consumerID)
                } else {
                    storage[consumerID] = addresses
                }
            }
            
            func contains(_ address: Address, for consumerID: UUID) -> Bool {
                guard let addresses = storage[consumerID] else { return false }
                return addresses.contains(address)
            }
            
            func addresses(for consumerID: UUID) -> Set<Address>? {
                storage[consumerID]
            }
            
        }
        
        var consumerContinuations: [UUID: AsyncThrowingStream<Notification.Event, Swift.Error>.Continuation] = .init()
        var addressBook: AddressBook = .init()
        var subscriptionStates: [Address: State] = .init()
        let configuration: Configuration
        let dependencies: Dependencies
        let telemetry: Telemetry
        let clock = ContinuousClock()
        
        public init(configuration: Configuration = .standard,
                    dependencies: Dependencies = .init(),
                    telemetry: Telemetry = .shared) {
            self.configuration = configuration
            self.dependencies = dependencies
            self.telemetry = telemetry
        }
        
        public init(configuration: Configuration = .standard,
                    repository: Storage.Repository.Subscriptions?) {
            if let repository {
                self.init(configuration: configuration,
                          dependencies: .storage(repository: repository))
            } else {
                self.init(configuration: configuration, dependencies: .init())
            }
        }
        
        public func makeStream(for addresses: [Address],
                               using service: Network.FulcrumService,
                               consumerID: UUID) async throws -> Stream {
            let uniqueAddresses = Set(addresses)
            let stream = AsyncThrowingStream<Notification.Event, Swift.Error>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                Task {
                    await self.register(consumerID: consumerID,
                                        addresses: uniqueAddresses,
                                        service: service,
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
                        using service: Network.FulcrumService) async throws {
            let uniqueAddresses = Set(addresses)
            guard !uniqueAddresses.isEmpty else { return }
            guard consumerContinuations[consumerID] != nil else { throw Error.consumerNotFound(consumerID) }
            addressBook.union(uniqueAddresses, for: consumerID)
            
            for address in uniqueAddresses {
                try await attach(consumerID: consumerID,
                                 address: address,
                                 service: service)
            }
        }
        
        public func remove(consumerID: UUID) async {
            await unregister(consumerID: consumerID)
        }
    }
}
