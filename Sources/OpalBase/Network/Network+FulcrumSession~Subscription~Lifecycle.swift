// Network+FulcrumSession~Subscription~Lifecycle.swift

import Foundation
import SwiftFulcrum

// MARK: - Streaming lifecycle
extension Network.FulcrumSession {
    func makeSubscription<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        method: SwiftFulcrum.Method,
        initialType: Initial.Type,
        notificationType: Notification.Type,
        options: SwiftFulcrum.Client.Call.Options
    ) async throws -> Subscription<Initial, Notification> {
        try ensureSessionReady()
        guard let fulcrum else { throw Error.sessionNotStarted }
        
        let normalizedOptions = Self.normalizeStreamingOptions(options)
        let response = try await fulcrum.submit(method: method,
                                                initialType: initialType,
                                                notificationType: notificationType,
                                                options: normalizedOptions)
        
        guard case .stream(let responseIdentifier, let initial, let updates, let cancel) = response else {
            throw Error.unexpectedResponse(method)
        }
        
        let descriptor = await StreamingCallDescriptor(identifier: responseIdentifier,
                                                       method: method,
                                                       options: normalizedOptions,
                                                       initial: initial,
                                                       updates: updates,
                                                       cancel: cancel)
        
        streamingCallDescriptors[responseIdentifier] = descriptor
        
        return Subscription(identifier: responseIdentifier,
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
    
    func prepareStreamingCallsForRestart() async {
        for descriptor in streamingCallDescriptors.values {
            await descriptor.prepareForRestart()
        }
        
        await resetFulcrumForRestart()
        state = .stopped
    }
    
    func cancelAllStreamingCalls() async {
        let descriptors = Array(streamingCallDescriptors.values)
        streamingCallDescriptors.removeAll()
        
        for descriptor in descriptors {
            await descriptor.cancelAndFinish()
        }
    }
    
    func restoreStreamingSubscriptions(using fulcrum: SwiftFulcrum.Fulcrum) async throws {
        guard !streamingCallDescriptors.isEmpty else { return }
        try ensureSessionReady(allowRestoring: true)
        
        var firstError: Swift.Error?
        
        for descriptor in Array(streamingCallDescriptors.values) {
            do {
                try await descriptor.resubscribe(using: self, fulcrum: fulcrum)
            } catch {
                await descriptor.prepareForRestart()
                if firstError == nil { firstError = error }
            }
        }
        
        if let firstError { throw Error.failedToRestoreSubscription(firstError) }
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
    
    func resubscribeExisting<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        _ descriptor: StreamingCallDescriptor<Initial, Notification>,
        using fulcrum: SwiftFulcrum.Fulcrum? = nil
    ) async throws -> Initial {
        let cancelHandler = await descriptor.prepareForResubscription()
        if let cancelHandler { await cancelHandler() }
        await descriptor.waitForCancellationCompletion()
        
        try ensureSessionReady(allowRestoring: true)
        
        let activeFulcrum: SwiftFulcrum.Fulcrum
        
        if let fulcrum {
            activeFulcrum = fulcrum
        } else {
            guard let currentFulcrum = self.fulcrum else { throw Error.sessionNotStarted }
            activeFulcrum = currentFulcrum
        }
        
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

// MARK: - Utilities
extension Network.FulcrumSession {
    static func normalizeStreamingOptions(
        _ options: SwiftFulcrum.Client.Call.Options
    ) -> SwiftFulcrum.Client.Call.Options {
        SwiftFulcrum.Client.Call.Options(timeout: options.timeout, token: nil)
    }
}
