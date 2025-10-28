// Network+FulcrumSession~Subscription.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
    public struct Subscription<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>: Sendable {
        fileprivate let storage: SubscriptionStorage<Initial, Notification>
        
        public var identifier: UUID { storage.identifier }
        public var updates: AsyncThrowingStream<Notification, Swift.Error> { storage.updates }
        
        public func fetchLatestInitialResponse() async -> Initial {
            await storage.fetchLatestInitialResponse()
        }
        
        public func checkIsActive() async -> Bool {
            await storage.checkIsActive()
        }
        
        public func cancel() async {
            await storage.cancel()
        }
        
        @discardableResult
        public func resubscribe() async throws -> Initial {
            try await storage.resubscribe()
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
        let descriptor = StreamingCallDescriptor(identifier: descriptorIdentifier,
                                                 method: method,
                                                 options: normalizedOptions,
                                                 initial: initial,
                                                 updates: updates,
                                                 cancel: cancel)
        
        streamingCallDescriptors[descriptorIdentifier] = descriptor
        
        let storage = SubscriptionStorage(session: self, descriptor: descriptor)
        return Subscription(storage: storage)
    }
    
    internal func prepareStreamingCallsForRestart() {
        for descriptor in streamingCallDescriptors.values {
            descriptor.prepareForRestart()
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
                descriptor.finish(with: error)
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
    ) -> Initial {
        descriptor.latestInitialResponse
    }
    
    private func isStreamingCallActive<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        _ descriptor: StreamingCallDescriptor<Initial, Notification>
    ) -> Bool {
        descriptor.isActive
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
        
        descriptor.update(initial: initial, updates: updates, cancel: cancel)
        return initial
    }
    
    func readLatestInitialResponse<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        for descriptor: StreamingCallDescriptor<Initial, Notification>
    ) async -> Initial {
        latestInitialResponse(for: descriptor)
    }
    
    func readIsStreamingCallActive<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        _ descriptor: StreamingCallDescriptor<Initial, Notification>
    ) async -> Bool {
        isStreamingCallActive(descriptor)
    }
}

// MARK: - Descriptor storage
private final class SubscriptionStorage<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>: @unchecked Sendable {
    private unowned let session: Network.FulcrumSession
    private let descriptor: StreamingCallDescriptor<Initial, Notification>
    private let updatesStream: AsyncThrowingStream<Notification, Swift.Error>
    
    init(session: Network.FulcrumSession, descriptor: StreamingCallDescriptor<Initial, Notification>) {
        self.session = session
        self.descriptor = descriptor
        self.updatesStream = descriptor.stream
    }
    
    var identifier: UUID { descriptor.identifier }
    
    var updates: AsyncThrowingStream<Notification, Swift.Error> { updatesStream }
    
    func fetchLatestInitialResponse() async -> Initial {
        await session.readLatestInitialResponse(for: descriptor)
    }
    
    func checkIsActive() async -> Bool {
        await session.readIsStreamingCallActive(descriptor)
    }
    
    func cancel() async {
        await session.cancelStreamingCall(for: descriptor)
    }
    
    func resubscribe() async throws -> Initial {
        try await session.resubscribeExisting(descriptor)
    }
}

class AnyStreamingCallDescriptor: @unchecked Sendable {
    let identifier: UUID
    let method: SwiftFulcrum.Method
    let options: SwiftFulcrum.Client.Call.Options
    
    init(identifier: UUID, method: SwiftFulcrum.Method, options: SwiftFulcrum.Client.Call.Options) {
        self.identifier = identifier
        self.method = method
        self.options = options
    }
    
    func prepareForRestart() {}
    func cancelAndFinish() async {}
    func finish(with error: Swift.Error) {}
    func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws {}
}

final class StreamingCallDescriptor<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>: AnyStreamingCallDescriptor, @unchecked Sendable {
    private var cancelHandler: (@Sendable () async -> Void)?
    private var forwardingTask: Task<Void, Never>?
    private let continuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation
    let stream: AsyncThrowingStream<Notification, Swift.Error>
    private(set) var latestInitialResponse: Initial
    private(set) var isActive = false
    
    init(identifier: UUID,
         method: SwiftFulcrum.Method,
         options: SwiftFulcrum.Client.Call.Options,
         initial: Initial,
         updates: AsyncThrowingStream<Notification, Swift.Error>,
         cancel: @escaping @Sendable () async -> Void) {
        var capturedContinuation: AsyncThrowingStream<Notification, Swift.Error>.Continuation!
        self.stream = AsyncThrowingStream { continuation in
            capturedContinuation = continuation
        }
        self.continuation = capturedContinuation
        self.latestInitialResponse = initial
        
        super.init(identifier: identifier, method: method, options: options)
        update(initial: initial, updates: updates, cancel: cancel)
    }
    
    override func prepareForRestart() {
        forwardingTask?.cancel()
        forwardingTask = nil
        cancelHandler = nil
        isActive = false
    }
    
    override func cancelAndFinish() async {
        forwardingTask?.cancel()
        forwardingTask = nil
        if let cancelHandler {
            await cancelHandler()
        }
        cancelHandler = nil
        isActive = false
        continuation.finish()
    }
    
    override func finish(with error: Swift.Error) {
        forwardingTask?.cancel()
        forwardingTask = nil
        cancelHandler = nil
        isActive = false
        continuation.finish(throwing: error)
    }
    
    override func resubscribe(using session: Network.FulcrumSession, fulcrum: SwiftFulcrum.Fulcrum) async throws {
        _ = try await session.resubscribeExisting(self, using: fulcrum)
    }
    
    func update(initial: Initial,
                updates: AsyncThrowingStream<Notification, Swift.Error>,
                cancel: @escaping @Sendable () async -> Void) {
        latestInitialResponse = initial
        cancelHandler = cancel
        forwardingTask?.cancel()
        forwardingTask = Task {
            do {
                for try await update in updates {
                    continuation.yield(update)
                }
                isActive = false
            } catch is CancellationError {
                isActive = false
            } catch {
                isActive = false
            }
        }
        isActive = true
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
