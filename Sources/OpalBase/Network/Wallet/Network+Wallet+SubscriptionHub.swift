// Network+Wallet+SubscriptionHub.swift

import Foundation
import SwiftFulcrum

extension Network.Wallet {
    public actor SubscriptionHub {
        public struct Notification: Sendable {
            public let address: Address
            public let status: String?
            public let isReplay: Bool
        }
        
        public struct Stream: Sendable {
            public let id: UUID
            public let notifications: AsyncThrowingStream<Notification, Swift.Error>
        }
        
        public enum Error: Swift.Error, Sendable {
            case consumerNotFound(UUID)
            case storageFailure(Address, Swift.Error)
            case subscriptionFailed(Address, Swift.Error)
        }
        
        private struct SubscriptionState {
            var consumers: Set<UUID> = .init()
            var lastStatus: String?
            var task: Task<Void, Never>?
            var cancel: (@Sendable () async -> Void)?
        }
        
        private var consumers: [UUID: AsyncThrowingStream<Notification, Swift.Error>.Continuation] = .init()
        private var consumerAddresses: [UUID: Set<Address>] = .init()
        private var subscriptions: [Address: SubscriptionState] = .init()
        private let repository: Storage.Repository.Subscriptions?
        
        public init(repository: Storage.Repository.Subscriptions? = nil) {
            self.repository = repository
        }
        
        public func makeStream(for addresses: [Address],
                               using fulcrum: Fulcrum,
                               consumerID: UUID) async throws -> Stream {
            let unique = Set(addresses)
            let stream = AsyncThrowingStream<Notification, Swift.Error>(bufferingPolicy: .bufferingNewest(1)) { continuation in
                Task {
                    await self.register(consumerID: consumerID,
                                        addresses: unique,
                                        fulcrum: fulcrum,
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
                        using fulcrum: Fulcrum) async throws {
            let unique = Set(addresses)
            guard !unique.isEmpty else { return }
            guard consumers[consumerID] != nil else { throw Error.consumerNotFound(consumerID) }
            consumerAddresses[consumerID, default: .init()].formUnion(unique)
            
            for address in unique {
                try await attach(consumerID: consumerID,
                                 address: address,
                                 fulcrum: fulcrum)
            }
        }
        
        public func remove(consumerID: UUID) async {
            await unregister(consumerID: consumerID)
        }
    }
}

extension Network.Wallet.SubscriptionHub {
    func register(consumerID: UUID,
                  addresses: Set<Address>,
                  fulcrum: Fulcrum,
                  continuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation) async {
        consumers[consumerID] = continuation
        consumerAddresses[consumerID, default: .init()].formUnion(addresses)
        
        for address in addresses {
            do {
                try await attach(consumerID: consumerID,
                                 address: address,
                                 fulcrum: fulcrum)
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
                fulcrum: Fulcrum) async throws {
        subscriptions[address, default: .init()].consumers.insert(consumerID)
        
        if let continuation = consumers[consumerID] {
            try await deliverReplay(for: address,
                                    to: continuation)
            guard isConsumerActive(consumerID: consumerID, address: address) else {
                await removeInactiveConsumer(consumerID, address: address)
                return
            }
        }
        
        guard isConsumerActive(consumerID: consumerID, address: address) else {
            await removeInactiveConsumer(consumerID, address: address)
            return
        }
        
        let lastStatus = subscriptions[address]?.lastStatus
        
        try await persist(address: address, isActive: true, lastStatus: lastStatus)
        guard isConsumerActive(consumerID: consumerID, address: address) else {
            await removeInactiveConsumer(consumerID, address: address)
            return
        }
        
        try await startStreamingIfNeeded(for: address, using: fulcrum)
    }
    
    func startStreamingIfNeeded(for address: Address, using fulcrum: Fulcrum) async throws {
        var state = subscriptions[address] ?? SubscriptionState()
        guard state.task == nil else { return }
        guard !state.consumers.isEmpty else { return }
        
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let (_, initialStatus, stream, cancel) = try await address.subscribe(fulcrum: fulcrum)
                if let failure = await self.recordInitialStatus(initialStatus,
                                                                for: address,
                                                                cancel: cancel) {
                    await self.finishSubscription(for: address, error: failure)
                    return
                }
                
                for try await notification in stream {
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
        let previous = state.lastStatus
        state.lastStatus = status
        state.cancel = cancel
        subscriptions[address] = state
        
        do {
            try await persist(address: address, isActive: true, lastStatus: status)
        } catch {
            return error
        }
        
        if previous != status {
            await broadcast(.init(address: address, status: status, isReplay: false), for: address)
        }
        
        return nil
    }
    
    func handle(notification: Response.Result.Blockchain.Address.SubscribeNotification,
                for address:Address) async {
        var state = subscriptions[address] ?? SubscriptionState()
        state.lastStatus = notification.status
        subscriptions[address] = state
        
        do {
            try await persist(address: address, isActive: true, lastStatus: notification.status)
        } catch {
            await finishSubscription(for: address, error: error)
            return
        }
        
        await broadcast(.init(address: address, status: notification.status, isReplay: false), for: address)
    }
    
    func finishSubscription(for address: Address, error: Swift.Error?) async {
        guard var state = subscriptions[address] else { return }
        state.task?.cancel()
        state.task = nil
        if let cancel = state.cancel { await cancel() }
        state.cancel = nil
        subscriptions[address] = state
        
        if let error {
            let wrapped = Error.subscriptionFailed(address, error)
            for consumerID in state.consumers {
                consumers[consumerID]?.finish(throwing: wrapped)
                consumerAddresses[consumerID]?.remove(address)
            }
            _ = try? await persist(address: address, isActive: false, lastStatus: state.lastStatus)
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
        if let cancel = state.cancel { await cancel() }
        state.cancel = nil
        subscriptions[address] = nil
        _ = try? await persist(address: address, isActive: false, lastStatus: state.lastStatus)
    }
    
    func broadcast(_ notification: Notification, for address: Address) async {
        guard let state = subscriptions[address] else { return }
        for consumerID in state.consumers {
            consumers[consumerID]?.yield(notification)
        }
    }
    
    func deliverReplay(for address: Address,
                       to continuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation) async throws {
        var state = subscriptions[address] ?? SubscriptionState()
        if state.lastStatus == nil, let repository {
            do {
                if let row = try await repository.byAddress(address.string) {
                    state.lastStatus = row.lastStatus
                }
            } catch {
                throw Error.storageFailure(address, error)
            }
        }
        
        if var current = subscriptions[address] {
            current.lastStatus = state.lastStatus
            subscriptions[address] = current
        }
        
        if let status = state.lastStatus {
            continuation.yield(.init(address: address, status: status, isReplay: true))
        }
    }
    
    private func isConsumerActive(consumerID: UUID, address: Address) -> Bool {
        guard consumers[consumerID] != nil else { return false }
        guard let addresses = consumerAddresses[consumerID],
              addresses.contains(address)
        else { return false }
        guard let state = subscriptions[address],
              state.consumers.contains(consumerID)
        else { return false }
        return true
    }
    
    private func removeInactiveConsumer(_ consumerID: UUID, address: Address) async {
        guard var state = subscriptions[address], state.consumers.contains(consumerID) else { return }
        state.consumers.remove(consumerID)
        subscriptions[address] = state
        if state.consumers.isEmpty {
            await tearDown(address: address)
        }
    }
    
    func persist(address: Address, isActive: Bool, lastStatus: String?) async throws {
        guard let repository else { return }
        do {
            try await repository.upsert(address: address.string,
                                        isActive: isActive,
                                        lastStatus: lastStatus)
        } catch {
            throw Error.storageFailure(address, error)
        }
    }
}
