// Network+Wallet+SubscriptionHub+AddressQueue.swift

import Foundation

extension Network.Wallet.SubscriptionHub {
    struct AddressQueue: Sendable {
        struct QueueItem: Sendable {
            let status: String?
            let replayFlag: Bool
            let enqueueInstant: ContinuousClock.Instant
        }
        
        struct EnqueueOutcome: Sendable {
            let enqueueInstant: ContinuousClock.Instant
            let immediateFlushFlag: Bool
        }
        
        var pendingItems: [QueueItem] = []
        var lastSequence: UInt64 = 0
        var lastStatus: String?
        var lastEnqueueInstant: ContinuousClock.Instant?
        
        mutating func enqueue(status: String?,
                              replayFlag: Bool,
                              clock: ContinuousClock,
                              configuration: Network.Wallet.SubscriptionHub.Configuration) -> EnqueueOutcome {
            let now = clock.now
            let item = QueueItem(status: status, replayFlag: replayFlag, enqueueInstant: now)
            
            if let lastIndex = pendingItems.indices.last,
               pendingItems[lastIndex].status == item.status,
               pendingItems[lastIndex].enqueueInstant.duration(to: now) <= configuration.maxDebounceInterval {
                pendingItems[lastIndex] = item
            } else {
                pendingItems.append(item)
            }
            
            lastEnqueueInstant = now
            return EnqueueOutcome(enqueueInstant: now,
                                  immediateFlushFlag: pendingItems.count >= configuration.maxBatchSize)
        }
        
        mutating func flush(address: Address,
                            flushedInstant: ContinuousClock.Instant) -> Network.Wallet.SubscriptionHub.Notification? {
            guard !pendingItems.isEmpty else { return nil }
            let firstInstant = pendingItems.first?.enqueueInstant ?? flushedInstant
            var events: [Network.Wallet.SubscriptionHub.Notification.Event] = []
            
            for item in pendingItems {
                lastSequence &+= 1
                events.append(.init(address: address,
                                    status: item.status,
                                    replayFlag: item.replayFlag,
                                    sequence: lastSequence))
                lastStatus = item.status
            }
            
            pendingItems.removeAll(keepingCapacity: true)
            
            return .init(address: address,
                         events: events,
                         enqueueInstant: firstInstant,
                         flushInstant: flushedInstant)
        }
    }
}
