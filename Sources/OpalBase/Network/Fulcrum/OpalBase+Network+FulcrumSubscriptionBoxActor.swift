// OpalBase+Network+FulcrumSubscriptionBoxActor.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network {
    actor FulcrumSubscriptionBoxActor<Initial: SwiftFulcrum.RPC.JSONRPCResponseAdapter, Notification: SwiftFulcrum.RPC.JSONRPCResponseAdapter>: FulcrumSubscriptionClient {
        let id: UUID
        let stream: AsyncThrowingStream<Notification, Swift.Error>

        private let method: SwiftFulcrum.RPC.Method
        private let options: SwiftFulcrum.Client.Call.Options
        let onTermination: @Sendable (UUID) async -> Void

        var continuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation
        var cancellationHandler: (@Sendable () async -> Void)?
        var forwardingTask: Task<Void, Never>?
        var forwardingGeneration: UInt64 = 0
        var isTerminated = false
        var isExpectingResubscribe = false
        var hasNotifiedTermination = false

        init(
            method: SwiftFulcrum.RPC.Method,
            options: SwiftFulcrum.Client.Call.Options,
            onTermination: @escaping @Sendable (UUID) async -> Void
        ) {
            self.id = UUID()
            self.method = method
            self.options = options
            self.onTermination = onTermination

            let (stream, continuation) = AsyncThrowingStream<Notification, Swift.Error>.makeStream()
            self.stream = stream
            self.continuation = continuation
        }

        func establish(using fulcrum: SwiftFulcrum.Client) async throws -> Initial {
            let (initial, updates, cancel) = try await fulcrum.subscribe(
                method: method,
                initialType: Initial.self,
                notificationType: Notification.self,
                options: options
            )

            cancellationHandler = cancel
            startForwarding(with: updates)
            return initial
        }

        func prepareForReconnect() async {
            guard !isTerminated else { return }
            isExpectingResubscribe = true
            let didHaveCancellationHandler = cancellationHandler != nil
            await tearDownCurrentHandler()
            if didHaveCancellationHandler {
                await waitForForwardingCompletion()
            } else {
                await stopForwardingAndWait()
            }
        }

        func resubscribe(using fulcrum: SwiftFulcrum.Client) async {
            guard !isTerminated else { return }
            do {
                isExpectingResubscribe = true
                let didHaveCancellationHandler = cancellationHandler != nil
                await tearDownCurrentHandler()
                if didHaveCancellationHandler {
                    await waitForForwardingCompletion()
                } else {
                    await stopForwardingAndWait()
                }
                let (_, updates, cancel) = try await fulcrum.subscribe(
                    method: method,
                    initialType: Initial.self,
                    notificationType: Notification.self,
                    options: options
                )

                cancellationHandler = cancel
                startForwarding(with: updates)
                isExpectingResubscribe = false
            } catch {
                await fail(with: error)
            }
        }

        func cancel() async {
            guard !isTerminated else { return }
            isTerminated = true
            await stopForwardingAndWait()
            continuation.finish()
            await tearDownCurrentHandler()
            await notifyTermination()
        }

        func fail(with error: Swift.Error) async {
            guard !isTerminated else { return }
            isTerminated = true
            await stopForwardingAndWait()
            continuation.finish(throwing: error)
            await tearDownCurrentHandler()
            await notifyTermination()
        }
    }
}

