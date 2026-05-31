// OpalBase+Network~FulcrumSubscriptionStream.swift

import Foundation

extension _OpalBase.Network {
    static func makeSubscriptionStream<Initial: Sendable, Notification: Sendable, Update: Sendable, DeduplicationKey: Sendable & Equatable>(
        initial: Initial,
        updates: AsyncThrowingStream<Notification, Swift.Error>,
        cancel: @escaping @Sendable () async -> Void,
        makeInitialUpdates: @escaping @Sendable (Initial) throws -> [Update],
        makeUpdates: @escaping @Sendable (Notification) throws -> [Update],
        deduplicationKey: @escaping @Sendable (Update) -> DeduplicationKey
    ) -> AsyncThrowingStream<Update, Swift.Error> {
        AsyncThrowingStream { continuation in
            var lastKey: DeduplicationKey?
            let initialValue = initial
            let updatesStream = updates
            let cancelSubscription = cancel
            let buildInitialUpdates = makeInitialUpdates
            let buildUpdates = makeUpdates
            let keyForDeduplication = deduplicationKey
            
            do {
                for update in try buildInitialUpdates(initialValue) {
                    lastKey = keyForDeduplication(update)
                    continuation.yield(update)
                }
            } catch {
                continuation.finish(throwing: FulcrumErrorTranslator.translate(error))
                Task { await cancelSubscription() }
                return
            }
            
            let task = Task {
                do {
                    for try await notification in updatesStream {
                        for update in try buildUpdates(notification) {
                            let key = keyForDeduplication(update)
                            guard key != lastKey else { continue }
                            lastKey = key
                            continuation.yield(update)
                        }
                    }
                    continuation.finish()
                } catch {
                    if error.isCancellationError {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: FulcrumErrorTranslator.translate(error))
                    }
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
                Task { await cancelSubscription() }
            }
        }
    }
}
