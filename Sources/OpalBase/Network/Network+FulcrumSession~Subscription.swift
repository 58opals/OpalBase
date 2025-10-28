// Network+FulcrumSession~Subscription.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public struct Subscription<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>: Sendable {
        private let fetchLatestInitialResponseHandler: @Sendable () async -> Initial
        private let checkIsActiveHandler: @Sendable () async -> Bool
        private let cancelHandler: @Sendable () async -> Void
        private let resubscribeHandler: @Sendable () async throws -> Initial
        
        public let identifier: UUID
        public let updates: AsyncThrowingStream<Notification, Swift.Error>
        
        init(identifier: UUID,
             updates: AsyncThrowingStream<Notification, Swift.Error>,
             fetchLatestInitialResponse: @escaping @Sendable () async -> Initial,
             checkIsActive: @escaping @Sendable () async -> Bool,
             cancel: @escaping @Sendable () async -> Void,
             resubscribe: @escaping @Sendable () async throws -> Initial) {
            self.identifier = identifier
            self.updates = updates
            self.fetchLatestInitialResponseHandler = fetchLatestInitialResponse
            self.checkIsActiveHandler = checkIsActive
            self.cancelHandler = cancel
            self.resubscribeHandler = resubscribe
        }
        
        public func fetchLatestInitialResponse() async -> Initial {
            await fetchLatestInitialResponseHandler()
        }
        
        public func checkIsActive() async -> Bool {
            await checkIsActiveHandler()
        }
        
        public func cancel() async {
            await cancelHandler()
        }
        
        public func resubscribe() async throws -> Initial {
            try await resubscribeHandler()
        }
    }
}

extension Network.FulcrumSession {
    public func subscribeToAddress(
        _ address: String,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Subscription<SwiftFulcrum.Response.Result.Blockchain.Address.Subscribe, SwiftFulcrum.Response.Result.Blockchain.Address.SubscribeNotification> {
        try await makeSubscription(
            method: .blockchain(.address(.subscribe(address: address))),
            initialType: SwiftFulcrum.Response.Result.Blockchain.Address.Subscribe.self,
            notificationType: SwiftFulcrum.Response.Result.Blockchain.Address.SubscribeNotification.self,
            options: options
        )
    }
    
    public func subscribeToScriptHash(
        _ scriptHash: String,
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Subscription<SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe, SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification> {
        try await makeSubscription(
            method: .blockchain(.scripthash(.subscribe(scripthash: scriptHash))),
            initialType: SwiftFulcrum.Response.Result.Blockchain.ScriptHash.Subscribe.self,
            notificationType: SwiftFulcrum.Response.Result.Blockchain.ScriptHash.SubscribeNotification.self,
            options: options
        )
    }
}

// MARK: - Streaming lifecycle
extension Network.FulcrumSession {
    private func makeSubscription<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        method: SwiftFulcrum.Method,
        initialType: Initial.Type,
        notificationType: Notification.Type,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> Subscription<Initial, Notification> {
        try ensureSessionIsRunning()
        guard let fulcrum else { throw Error.sessionNotStarted }
        
        let normalizedOptions = Self.normalizeStreamingOptions(options)
        let response = try await fulcrum.submit(method: method,
                                                initialType: initialType,
                                                notificationType: notificationType,
                                                options: options)
        
        guard case .stream(let responseID, let initial, let updates, let cancel) = response else {
            throw Error.unexpectedResponse(method)
        }
        
        let descriptorIdentifier = responseID
        let descriptor = await StreamingCallDescriptor(identifier: descriptorIdentifier,
                                                       method: method,
                                                       options: normalizedOptions,
                                                       initial: initial,
                                                       updates: updates,
                                                       cancel: cancel)
        
        streamingCallDescriptors[descriptorIdentifier] = descriptor
        
        return Subscription(identifier: descriptorIdentifier,
                            updates: descriptor.stream,
                            fetchLatestInitialResponse: { [weak session = self, descriptor] in
            guard let session else { return await descriptor.readLatestInitialResponse() }
            return await session.latestInitialResponse(for: descriptor)
        },
                            checkIsActive: { [weak session = self, descriptor] in
            guard let session else { return await descriptor.readIsActive() }
            return await session.isStreamingCallActive(descriptor)
        },
                            cancel: { [weak session = self, descriptor] in
            guard let session else { return await descriptor.cancelAndFinish() }
            await session.cancelStreamingCall(for: descriptor)
        },
                            resubscribe: { [weak session = self, descriptor] in
            guard let session else { return await descriptor.readLatestInitialResponse() }
            return try await session.resubscribeExisting(descriptor)
        })
    }
    
    internal func prepareStreamingCallsForRestart() async {
        for descriptor in streamingCallDescriptors.values {
            await descriptor.prepareForRestart()
        }
    }
    
    internal func cancelAllStreamingCalls() async {
        let descriptors = Array(streamingCallDescriptors.values)
        streamingCallDescriptors.removeAll()
        
        for descriptor in descriptors {
            await descriptor.cancelAndFinish()
        }
    }
    
    internal func restoreStreamingSubscriptions(using fulcrum: SwiftFulcrum.Fulcrum) async {
        guard !streamingCallDescriptors.isEmpty else { return }
        
        for descriptor in Array(streamingCallDescriptors.values) {
            do {
                try await descriptor.resubscribe(using: self, fulcrum: fulcrum)
            } catch {
                await descriptor.finish(with: error)
                streamingCallDescriptors.removeValue(forKey: descriptor.identifier)
            }
        }
    }
    
    func cancelStreamingCall<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        for descriptor: StreamingCallDescriptor<Initial, Notification>
    ) async {
        guard streamingCallDescriptors.removeValue(forKey: descriptor.identifier) != nil else { return }
        await descriptor.cancelAndFinish()
    }
    
    private func latestInitialResponse<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        for descriptor: StreamingCallDescriptor<Initial, Notification>
    ) async -> Initial {
        await descriptor.readLatestInitialResponse()
    }
    
    private func isStreamingCallActive<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        _ descriptor: StreamingCallDescriptor<Initial, Notification>
    ) async -> Bool {
        await descriptor.readIsActive()
    }
    
    internal func resubscribeExisting<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        _ descriptor: StreamingCallDescriptor<Initial, Notification>,
        using fulcrum: SwiftFulcrum.Fulcrum? = nil
    ) async throws -> Initial {
        try ensureSessionIsRunning()
        let activeFulcrum = fulcrum ?? self.fulcrum
        guard let activeFulcrum else { throw Error.sessionNotStarted }
        
        let response = try await activeFulcrum.submit(method: descriptor.method,
                                                      initialType: Initial.self,
                                                      notificationType: Notification.self,
                                                      options: descriptor.options)
        
        guard case .stream(_, let initial, let updates, let cancel) = response else {
            throw Error.unexpectedResponse(descriptor.method)
        }
        
        await descriptor.update(initial: initial, updates: updates, cancel: cancel)
        return initial
    }
    
    func readLatestInitialResponse<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        for descriptor: StreamingCallDescriptor<Initial, Notification>
    ) async -> Initial {
        await latestInitialResponse(for: descriptor)
    }
    
    func readIsStreamingCallActive<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        _ descriptor: StreamingCallDescriptor<Initial, Notification>
    ) async -> Bool {
        await isStreamingCallActive(descriptor)
    }
}

// MARK: - Descriptor storage
protocol AnyStreamingCallDescriptor: Sendable {
    var identifier: UUID { get }
    var method: SwiftFulcrum.Method { get }
    var options: SwiftFulcrum.Client.Call.Options { get }
    
    func prepareForRestart() async
    func cancelAndFinish() async
    func finish(with error: Swift.Error) async
    func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws
}

actor StreamingCallDescriptor<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>: AnyStreamingCallDescriptor {
    let identifier: UUID
    let method: SwiftFulcrum.Method
    let options: SwiftFulcrum.Client.Call.Options
    let stream: AsyncThrowingStream<Notification, Swift.Error>
    
    private var cancelHandler: (@Sendable () async -> Void)?
    private var forwardingTask: Task<Void, Never>?
    private let continuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation
    
    private var latestInitialResponse: Initial
    private var isActive = false
    
    init(identifier: UUID,
         method: SwiftFulcrum.Method,
         options: SwiftFulcrum.Client.Call.Options,
         initial: Initial,
         updates: AsyncThrowingStream<Notification, Swift.Error>,
         cancel: @escaping @Sendable () async -> Void) async {
        self.identifier = identifier
        self.method = method
        self.options = options
        
        var capturedContinuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation!
        let stream = AsyncThrowingStream<Notification, Swift.Error> { continuation in
            capturedContinuation = continuation
        }
        
        self.stream = stream
        self.continuation = capturedContinuation
        self.latestInitialResponse = initial
        self.cancelHandler = cancel
        
        update(initial: initial, updates: updates, cancel: cancel)
    }
    
    func prepareForRestart() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        cancelHandler = nil
        isActive = false
    }
    
    func cancelAndFinish() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        if let cancelHandler {
            await cancelHandler()
        }
        cancelHandler = nil
        isActive = false
        continuation.finish()
    }
    
    func finish(with error: Swift.Error) async {
        forwardingTask?.cancel()
        forwardingTask = nil
        cancelHandler = nil
        isActive = false
        continuation.finish(throwing: error)
    }
    
    func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws {
        _ = try await session.resubscribeExisting(self, using: fulcrum)
    }
    
    func update(initial: Initial,
                updates: AsyncThrowingStream<Notification, Swift.Error>,
                cancel: @escaping @Sendable () async -> Void) {
        latestInitialResponse = initial
        cancelHandler = cancel
        forwardingTask?.cancel()
        forwardingTask = Task { [weak self] in
            guard let self else { return }
            await self.forwardUpdates(from: updates)
        }
        isActive = true
    }
    
    private func forwardUpdates(from updates: AsyncThrowingStream<Notification, Swift.Error>) async {
        do {
            for try await update in updates {
                continuation.yield(update)
            }
            isActive = false
            forwardingTask = nil
        } catch is CancellationError {
            isActive = false
            forwardingTask = nil
        } catch {
            isActive = false
            forwardingTask = nil
        }
    }
    
    func readLatestInitialResponse() -> Initial {
        latestInitialResponse
    }
    
    func readIsActive() -> Bool {
        isActive
    }
}

// MARK: - Utilities
extension Network.FulcrumSession {
    fileprivate static func normalizeStreamingOptions(
        _ options: SwiftFulcrum.Client.Call.Options
    ) -> SwiftFulcrum.Client.Call.Options {
        SwiftFulcrum.Client.Call.Options(timeout: options.timeout, token: nil)
    }
}
