// Network+FulcrumSubscriptionStream.swift

import Foundation

extension Network {
    static func makeSubscriptionStream<Initial: Sendable, Notification: Sendable, Update: Sendable, DeduplicationKey: Sendable & Equatable>(
        initial: Initial,
        updates: AsyncThrowingStream<Notification, Swift.Error>,
        cancel: @escaping @Sendable () async -> Void,
        makeInitialUpdates: @escaping @Sendable (Initial) -> [Update],
        makeUpdates: @escaping @Sendable (Notification) -> [Update],
        deduplicationKey: @escaping @Sendable (Update) -> DeduplicationKey
    ) -> AsyncThrowingStream<Update, Swift.Error> {
        AsyncThrowingStream { continuation in
            var lastKey: DeduplicationKey?
            let initialValue = initial
            let updatesStream = updates
            let cancelHandler = cancel
            let makeInitialUpdatesHandler = makeInitialUpdates
            let makeUpdatesHandler = makeUpdates
            let deduplicationKeyHandler = deduplicationKey
            
            for update in makeInitialUpdatesHandler(initialValue) {
                lastKey = deduplicationKeyHandler(update)
                continuation.yield(update)
            }
            
            let task = Task {
                do {
                    for try await notification in updatesStream {
                        for update in makeUpdatesHandler(notification) {
                            let key = deduplicationKeyHandler(update)
                            guard key != lastKey else { continue }
                            lastKey = key
                            continuation.yield(update)
                        }
                    }
                    continuation.finish()
                } catch {
                    if error.checkCancellation {
                        continuation.finish()
                    } else {
                        continuation.finish(throwing: FulcrumErrorTranslator.translate(error))
                    }
                }
            }
            
            continuation.onTermination = { _ in
                task.cancel()
                Task { await cancelHandler() }
            }
        }
    }
}
