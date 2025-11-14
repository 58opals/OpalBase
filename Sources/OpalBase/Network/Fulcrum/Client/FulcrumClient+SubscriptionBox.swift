// Network+FulcrumClient+SubscriptionBox.swift

import Foundation
import SwiftFulcrum

extension Network {
    actor FulcrumSubscriptionBox<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>: FulcrumSubscription {
        let id: UUID
        let stream: AsyncThrowingStream<Notification, Swift.Error>
        
        private let method: SwiftFulcrum.Method
        private let options: Client.Call.Options
        private let onTermination: @Sendable (UUID) async -> Void
        
        private var continuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation
        private var cancelHandler: (@Sendable () async -> Void)?
        private var forwardingTask: Task<Void, Never>?
        private var forwardingGeneration: UInt64 = 0
        private var isTerminated = false
        private var isExpectingResubscribe = false
        private var hasNotifiedTermination = false
        
        init(
            method: SwiftFulcrum.Method,
            options: Client.Call.Options,
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
        
        func establish(using fulcrum: Fulcrum) async throws -> Initial {
            let response = try await fulcrum.submit(
                method: method,
                initialType: Initial.self,
                notificationType: Notification.self,
                options: options
            )
            guard let stream = response.extractSubscriptionStream() else {
                throw Fulcrum.Error.client(.protocolMismatch("Expected subscription stream for method: \(method)"))
            }
            let (initial, updates, cancel) = stream
            cancelHandler = cancel
            startForwarding(with: updates)
            return initial
        }
        
        func prepareForReconnect() async {
            guard !isTerminated else { return }
            isExpectingResubscribe = true
            forwardingTask?.cancel()
        }
        
        func resubscribe(using fulcrum: Fulcrum) async {
            guard !isTerminated else { return }
            do {
                await tearDownCurrentHandler()
                let response = try await fulcrum.submit(
                    method: method,
                    initialType: Initial.self,
                    notificationType: Notification.self,
                    options: options
                )
                guard let stream = response.extractSubscriptionStream() else {
                    let mismatch = Fulcrum.Error.client(.protocolMismatch("Expected subscription stream for method: \(method)"))
                    await fail(with: mismatch)
                    return
                }
                let (_, updates, cancel) = stream
                cancelHandler = cancel
                startForwarding(with: updates)
                isExpectingResubscribe = false
            } catch {
                await fail(with: error)
            }
        }
        
        func cancel() async {
            guard !isTerminated else { return }
            isTerminated = true
            forwardingTask?.cancel()
            await forwardingTask?.value
            continuation.finish()
            await tearDownCurrentHandler()
            await notifyTermination()
        }
        
        func fail(with error: Swift.Error) async {
            guard !isTerminated else { return }
            isTerminated = true
            forwardingTask?.cancel()
            await forwardingTask?.value
            continuation.finish(throwing: error)
            await tearDownCurrentHandler()
            await notifyTermination()
        }
        
        private func startForwarding(with updates: AsyncThrowingStream<Notification, Swift.Error>) {
            forwardingTask?.cancel()
            forwardingGeneration &+= 1
            let generation = forwardingGeneration
            forwardingTask = Task {
                await self.forward(updates: updates, generation: generation)
            }
        }
        
        private func forward(updates: AsyncThrowingStream<Notification, Swift.Error>, generation: UInt64) async {
            do {
                for try await update in updates {
                    continuation.yield(update)
                }
                
                if await shouldDeferTerminationForRecovery() {
                    return
                }
                
                await finishStream(for: generation)
            } catch is CancellationError {
                if await shouldDeferTerminationForRecovery() {
                    return
                }
                
                await finishStream(for: generation)
            } catch {
                if isExpectingResubscribe && isRecoverable(error) {
                    return
                }
                
                if await shouldDeferTerminationForRecovery() {
                    return
                }
                
                await finishStream(for: generation, with: error)
            }
        }
        
        private func shouldDeferTerminationForRecovery() async -> Bool {
            await Task.yield()
            
            if isTerminated {
                return true
            }
            
            if isExpectingResubscribe {
                return true
            }
            
            return false
        }
        
        private func finishStream(for generation: UInt64, with error: Swift.Error? = nil) async {
            guard generation == forwardingGeneration else { return }
            guard !isTerminated else { return }
            isTerminated = true
            forwardingTask?.cancel()
            if let error {
                continuation.finish(throwing: error)
            } else {
                continuation.finish()
            }
            await tearDownCurrentHandler()
            await notifyTermination()
        }
        
        private func notifyTermination() async {
            guard !hasNotifiedTermination else { return }
            hasNotifiedTermination = true
            await onTermination(id)
        }
        
        private func tearDownCurrentHandler() async {
            guard let handler = cancelHandler else { return }
            cancelHandler = nil
            await handler()
        }
        
        private func isRecoverable(_ error: Swift.Error) -> Bool {
            guard let fulcrumError = error as? Fulcrum.Error else { return false }
            switch fulcrumError {
            case .transport(.connectionClosed),
                    .transport(.reconnectFailed),
                    .transport(.heartbeatTimeout),
                    .client(.cancelled):
                return true
            default:
                return false
            }
        }
    }
}
