// Network+Wallet+SubscriptionHub~QueueManagement.swift

import Foundation

extension Network.Wallet.SubscriptionHub {
    func enqueue(status: String?,
                 replayFlag: Bool,
                 for address: Address,
                 bypassDebounce: Bool) async {
        var state = subscriptionStates[address] ?? State()
        let outcome = state.queue.enqueue(status: status,
                                          replayFlag: replayFlag,
                                          clock: clock,
                                          configuration: configuration)
        subscriptionStates[address] = state
        
        if outcome.immediateFlushFlag || bypassDebounce {
            await flushQueue(for: address, reason: bypassDebounce ? "bypass" : "capacity")
            return
        }
        
        scheduleFlushTask(for: address)
    }
    
    func scheduleFlushTask(for address: Address) {
        guard var state = subscriptionStates[address], !state.queue.pendingItems.isEmpty else { return }
        state.flushTask?.cancel()
        let now = clock.now
        let lastEnqueueInstant = state.queue.lastEnqueueInstant ?? now
        let debounceTarget = now + configuration.debounceInterval
        let maxTarget = lastEnqueueInstant + configuration.maxDebounceInterval
        let target = debounceTarget < maxTarget ? debounceTarget : maxTarget
        
        state.flushTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await clock.sleep(until: target, tolerance: .milliseconds(5))
            } catch { }
            await self.flushQueue(for: address, reason: "debounce")
        }
        
        subscriptionStates[address] = state
    }
    
    func flushQueue(for address: Address, reason: String) async {
        guard var state = subscriptionStates[address] else { return }
        guard let batch = state.queue.flush(address: address, flushedInstant: clock.now) else { return }
        
        state.flushTask?.cancel()
        state.flushTask = nil
        subscriptionStates[address] = state
        
        var awaitedOperations = 0
        
        if dependencies.hasPersistenceWriter {
            awaitedOperations += 1
            do {
                try await dependencies.persist(
                    .init(address: address,
                          activationFlag: true,
                          lastStatus: batch.events.last?.status)
                )
            } catch {
                await finishSubscription(for: address, error: Error.storageFailure(address, error))
                return
            }
        }
        
        await fanOutBatch(batch)
        
        await recordTelemetry(for: address,
                              batch: batch,
                              reason: reason,
                              awaitedOperations: awaitedOperations)
    }
    
    func fanOutBatch(_ batch: Notification) async {
        guard let state = subscriptionStates[batch.address] else { return }
        for consumerID in state.consumerIdentifiers {
            guard let continuation = consumerContinuations[consumerID] else { continue }
            for event in batch.events {
                continuation.yield(event)
            }
        }
    }
}
