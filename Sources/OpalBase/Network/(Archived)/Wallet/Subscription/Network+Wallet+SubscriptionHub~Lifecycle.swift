// Network+Wallet+SubscriptionHub~Lifecycle.swift

import Foundation

extension Network.Wallet.SubscriptionHub {
    func register(consumerID: UUID,
                  addresses: Set<Address>,
                  node: Network.Wallet.Node,
                  continuation: AsyncThrowingStream<Notification.Event, Swift.Error>.Continuation) async {
        consumerContinuations[consumerID] = continuation
        addressBook.union(addresses, for: consumerID)
        
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
        guard let addresses = addressBook.removeAddresses(for: consumerID) else { return }
        consumerContinuations.removeValue(forKey: consumerID)?.finish()
        
        for address in addresses {
            guard var state = subscriptionStates[address] else { continue }
            state.consumerIdentifiers.remove(consumerID)
            subscriptionStates[address] = state
            if state.consumerIdentifiers.isEmpty {
                await tearDownSubscription(address: address)
            }
        }
    }
    
    func attach(consumerID: UUID,
                address: Address,
                node: Network.Wallet.Node) async throws {
        var state = subscriptionStates[address] ?? State()
        state.consumerIdentifiers.insert(consumerID)
        subscriptionStates[address] = state
        
        if let continuation = consumerContinuations[consumerID] {
            try await deliverReplayEvents(for: address, to: continuation)
            guard checkConsumerIsActive(consumerID: consumerID, address: address) else {
                await removeInactiveConsumer(consumerID, address: address)
                return
            }
        }
        
        guard checkConsumerIsActive(consumerID: consumerID, address: address) else {
            await removeInactiveConsumer(consumerID, address: address)
            return
        }
        
        try await startStreamingIfNeeded(for: address, using: node)
    }
    
    func detach(consumerID: UUID, address: Address) async {
        guard var state = subscriptionStates[address] else { return }
        state.consumerIdentifiers.remove(consumerID)
        subscriptionStates[address] = state
        if state.consumerIdentifiers.isEmpty {
            await tearDownSubscription(address: address)
        }
    }
    
    func startStreamingIfNeeded(for address: Address,
                                using node: Network.Wallet.Node) async throws {
        var state = subscriptionStates[address] ?? State()
        guard state.streamTask == nil else { return }
        guard !state.consumerIdentifiers.isEmpty else { return }
        
        let task = Task { [weak self] in
            guard let self else { return }
            do {
                let subscription = try await node.subscribe(to: address)
                if let failure = await self.recordInitialStatusValue(subscription.initialStatus,
                                                                     for: address,
                                                                     cancelAction: subscription.cancel) {
                    await self.finishSubscription(for: address, error: failure)
                    return
                }
                
                for try await notification in subscription.updates {
                    await self.handleIncomingNotification(notification: notification, for: address)
                }
                await self.finishSubscription(for: address, error: nil)
            } catch {
                await self.finishSubscription(for: address, error: error)
            }
        }
        
        state.streamTask = task
        subscriptionStates[address] = state
    }
    
    func recordInitialStatusValue(_ status: String,
                                  for address: Address,
                                  cancelAction: @escaping @Sendable () async -> Void) async -> Swift.Error? {
        var state = subscriptionStates[address] ?? State()
        state.cancelAction = cancelAction
        subscriptionStates[address] = state
        
        await enqueue(status: status, replayFlag: false, for: address, bypassDebounce: true)
        
        return nil
    }
    
    func handleIncomingNotification(notification: Network.Wallet.SubscriptionStream.Notification,
                                    for address: Address) async {
        await enqueue(status: notification.status, replayFlag: false, for: address, bypassDebounce: false)
    }
    
    func finishSubscription(for address: Address, error: Swift.Error?) async {
        guard var state = subscriptionStates[address] else { return }
        state.streamTask?.cancel()
        state.streamTask = nil
        state.flushTask?.cancel()
        state.flushTask = nil
        if let cancelAction = state.cancelAction { await cancelAction() }
        state.cancelAction = nil
        subscriptionStates[address] = state
        
        if let error {
            let wrapped = Error.subscriptionFailed(address, error)
            for consumerID in state.consumerIdentifiers {
                consumerContinuations[consumerID]?.finish(throwing: wrapped)
                addressBook.remove(address, for: consumerID)
            }
            await persistInactiveState(address: address, lastStatus: state.queue.lastStatus)
            subscriptionStates[address] = nil
            return
        }
        
        if state.consumerIdentifiers.isEmpty {
            await tearDownSubscription(address: address)
        } else {
            subscriptionStates[address] = state
        }
    }
    
    func tearDownSubscription(address: Address) async {
        guard var state = subscriptionStates[address] else { return }
        state.streamTask?.cancel()
        state.streamTask = nil
        state.flushTask?.cancel()
        state.flushTask = nil
        if let cancelAction = state.cancelAction { await cancelAction() }
        state.cancelAction = nil
        subscriptionStates[address] = nil
        await persistInactiveState(address: address, lastStatus: state.queue.lastStatus)
    }
    
    func deliverReplayEvents(for address: Address,
                             to continuation: AsyncThrowingStream<Notification.Event, Swift.Error>.Continuation) async throws {
        var state = subscriptionStates[address] ?? State()
        if state.queue.lastStatus == nil, dependencies.hasPersistenceLoader {
            do {
                if let stored = try await dependencies.load(address: address) {
                    state.queue.lastStatus = stored.lastStatus
                }
            } catch {
                throw Error.storageFailure(address, error)
            }
        }
        
        subscriptionStates[address] = state
        
        if let stream = dependencies.replayStream(for: address, lastStatus: state.queue.lastStatus) {
            do {
                for try await replay in stream {
                    await enqueue(status: replay.status, replayFlag: true, for: address, bypassDebounce: true)
                }
            } catch {
                throw Error.storageFailure(address, error)
            }
            await flushQueue(for: address, reason: "replay")
        } else if let status = state.queue.lastStatus {
            var refreshed = subscriptionStates[address] ?? State()
            refreshed.queue.lastSequence &+= 1
            refreshed.queue.lastStatus = status
            subscriptionStates[address] = refreshed
            continuation.yield(
                .init(address: address, status: status, replayFlag: true, sequence: refreshed.queue.lastSequence)
            )
        }
    }
    
    func checkConsumerIsActive(consumerID: UUID, address: Address) -> Bool {
        guard consumerContinuations[consumerID] != nil else { return false }
        guard addressBook.contains(address, for: consumerID)
        else { return false }
        guard let state = subscriptionStates[address],
              state.consumerIdentifiers.contains(consumerID)
        else { return false }
        return true
    }
    
    func removeInactiveConsumer(_ consumerID: UUID, address: Address) async {
        await detach(consumerID: consumerID, address: address)
    }
}
