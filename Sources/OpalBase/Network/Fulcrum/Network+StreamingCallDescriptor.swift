// Network+StreamingCallDescriptor.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    actor StreamingCallDescriptor<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>: AnyStreamingCallDescriptor {
        let identifier: UUID
        let method: SwiftFulcrum.Method
        let stream: AsyncThrowingStream<Notification, Swift.Error>
        
        private var cancelHandler: (@Sendable () async -> Void)?
        private var forwardingTask: Task<Void, Never>?
        private let continuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation
        
        private var latestInitialResponse: Initial
        private var isActive = false
        private var shouldForwardUpdates = true
        private var pendingCancellationContinuations: [CheckedContinuation<Void, Never>] = .init()
        
        init(identifier: UUID,
             method: SwiftFulcrum.Method,
             initial: Initial,
             updates: AsyncThrowingStream<Notification, Swift.Error>,
             cancel: @escaping @Sendable () async -> Void) async {
            self.identifier = identifier
            self.method = method
            
            var capturedContinuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation!
            let stream = AsyncThrowingStream<Notification, Swift.Error> { continuation in
                capturedContinuation = continuation
            }
            
            self.stream = stream
            self.continuation = capturedContinuation
            self.latestInitialResponse = initial
            self.cancelHandler = cancel
            
            await update(initial: initial, updates: updates, cancel: cancel)
        }
        
        func prepareForRestart() async {
            let cancelHandler = await prepareForResubscription()
            if let cancelHandler { await cancelHandler() }
            await waitForCancellationCompletion()
        }
        
        func cancelAndFinish() async {
            let cancelHandler = await prepareForResubscription()
            if let cancelHandler { await cancelHandler() }
            await waitForCancellationCompletion()
            continuation.finish()
        }
        
        func finish(with error: Swift.Error) async {
            shouldForwardUpdates = false
            cancelHandler = nil
            isActive = false
            forwardingTask?.cancel()
            forwardingTask = nil
            continuation.finish(throwing: error)
            notifyCancellationCompletion()
        }
        
        func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws {
            _ = try await session.resubscribeExisting(self, using: fulcrum)
        }
        
        func update(initial: Initial,
                    updates: AsyncThrowingStream<Notification, Swift.Error>,
                    cancel: @escaping @Sendable () async -> Void) async {
            latestInitialResponse = initial
            cancelHandler = cancel
            await cancelForwardingTaskAndWait()
            forwardingTask = Task { [weak self] in
                guard let self else { return }
                await self.forwardUpdates(from: updates)
            }
            isActive = true
            shouldForwardUpdates = true
        }
        
        private func forwardUpdates(from updates: AsyncThrowingStream<Notification, Swift.Error>) async {
            var caughtError: Swift.Error?
            
            do {
                for try await update in updates {
                    if shouldForwardUpdates {
                        continuation.yield(update)
                    }
                }
            } catch {
                caughtError = error
            }
            isActive = false
            forwardingTask = nil
            
            if let caughtError {
                if shouldForwardUpdates {
                    continuation.finish(throwing: caughtError)
                }
            } else if shouldForwardUpdates {
                continuation.finish()
            }
            
            notifyCancellationCompletion()
        }
        
        func readLatestInitialResponse() -> Initial {
            latestInitialResponse
        }
        
        func readIsActive() -> Bool {
            isActive
        }
        
        private func cancelForwardingTaskAndWait() async {
            guard let currentTask = forwardingTask else { return }
            forwardingTask = nil
            currentTask.cancel()
            await currentTask.value
        }
        
        private func notifyCancellationCompletion() {
            guard !pendingCancellationContinuations.isEmpty else { return }
            let continuations = pendingCancellationContinuations
            pendingCancellationContinuations.removeAll()
            for continuation in continuations {
                continuation.resume()
            }
        }
        
        func prepareForResubscription() async -> (@Sendable () async -> Void)? {
            shouldForwardUpdates = false
            let handler = cancelHandler
            cancelHandler = nil
            isActive = false
            return handler
        }
        
        func waitForCancellationCompletion() async {
            guard forwardingTask != nil else { return }
            await withCheckedContinuation { continuation in
                pendingCancellationContinuations.append(continuation)
            }
        }
    }
}
