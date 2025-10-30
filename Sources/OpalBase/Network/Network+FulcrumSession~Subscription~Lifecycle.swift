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
                                                       initial: initial,
                                                       updates: updates,
                                                       cancel: cancel)
        
        streamingCallDescriptors[responseIdentifier] = descriptor
        streamingCallOptions[responseIdentifier] = normalizedOptions
        internallyCancelledStreamingCallIdentifiers.remove(responseIdentifier)
        
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
            if streamingCallOptions[descriptor.identifier]?.token != nil {
                internallyCancelledStreamingCallIdentifiers.insert(descriptor.identifier)
            }
            await descriptor.prepareForRestart()
        }
        
        setActiveServerAddress(nil)
        await resetFulcrumForRestart()
        state = .stopped
    }
    
    func cancelAllStreamingCalls() async {
        let descriptors = Array(streamingCallDescriptors.values)
        streamingCallDescriptors.removeAll()
        
        for descriptor in descriptors {
            streamingCallOptions.removeValue(forKey: descriptor.identifier)
            internallyCancelledStreamingCallIdentifiers.remove(descriptor.identifier)
        }
        
        for descriptor in descriptors { await descriptor.cancelAndFinish() }
    }
    
    func restoreStreamingSubscriptions(using fulcrum: SwiftFulcrum.Fulcrum) async throws {
        let previousFulcrum = self.fulcrum
        let previousState = state
        
        self.fulcrum = fulcrum
        
        guard !streamingCallDescriptors.isEmpty else { return }
        if previousState == .stopped {
            state = .restoring
        }
        
        do {
            try ensureSessionReady(allowRestoring: true)
            
            var firstError: Swift.Error?
            
            for descriptor in Array(streamingCallDescriptors.values) {
                let identifier = descriptor.identifier
                let options = streamingCallOptions[identifier]
                
                if let token = options?.token,
                   await token.isCancelled,
                   !internallyCancelledStreamingCallIdentifiers.contains(identifier) {
                    streamingCallDescriptors.removeValue(forKey: identifier)
                    streamingCallOptions.removeValue(forKey: identifier)
                    await descriptor.cancelAndFinish()
                    continue
                }
                
                do {
                    try await descriptor.resubscribe(using: self, fulcrum: fulcrum)
                } catch {
                    await descriptor.prepareForRestart()
                    if firstError == nil { firstError = error }
                }
            }
            if let firstError {
                state = previousState
                self.fulcrum = previousFulcrum
                throw Error.failedToRestoreSubscription(firstError)
            }
            
            if previousState == .stopped {
                state = .running
            }
        } catch {
            state = previousState
            self.fulcrum = previousFulcrum
            throw error
        }
    }
    
    func cancelStreamingCall<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
        for descriptor: StreamingCallDescriptor<Initial, Notification>
    ) async {
        let identifier = descriptor.identifier
        guard streamingCallDescriptors.removeValue(forKey: identifier) != nil else { return }
        streamingCallOptions.removeValue(forKey: identifier)
        internallyCancelledStreamingCallIdentifiers.remove(identifier)
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
        let identifier = descriptor.identifier
        var options = streamingCallOptions[identifier] ?? .init()
        try ensureSessionReady(allowRestoring: true)
        
        let activeFulcrum: SwiftFulcrum.Fulcrum
        
        if let fulcrum {
            activeFulcrum = fulcrum
        } else {
            guard let currentFulcrum = self.fulcrum else { throw Error.sessionNotStarted }
            activeFulcrum = currentFulcrum
        }
        
        let cancelHandler = await descriptor.prepareForResubscription()
        if let cancelHandler {
            if options.token != nil {
                internallyCancelledStreamingCallIdentifiers.insert(identifier)
            }
            await cancelHandler()
        }
        await descriptor.waitForCancellationCompletion()
        
        if let token = options.token, await token.isCancelled {
            options.token = SwiftFulcrum.Client.Call.Token()
            streamingCallOptions[identifier] = options
        }
        
        let response = try await activeFulcrum.submit(method: descriptor.method,
                                                      initialType: Initial.self,
                                                      notificationType: Notification.self,
                                                      options: options)
        
        guard case .stream(_, let initial, let updates, let cancel) = response else {
            throw Error.unexpectedResponse(descriptor.method)
        }
        
        await descriptor.update(initial: initial, updates: updates, cancel: cancel)
        streamingCallOptions[identifier] = options
        internallyCancelledStreamingCallIdentifiers.remove(identifier)
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
        SwiftFulcrum.Client.Call.Options(timeout: options.timeout, token: options.token)
    }
}
