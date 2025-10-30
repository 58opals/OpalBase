// Network~Subscription~API.swift

import Foundation
import SwiftFulcrum

extension Network.FulcrumSession {
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
    
    public func subscribeToChainHeaders(
        options: SwiftFulcrum.Client.Call.Options = .init()
    ) async throws -> Subscription<SwiftFulcrum.Response.Result.Blockchain.Headers.Subscribe, SwiftFulcrum.Response.Result.Blockchain.Headers.SubscribeNotification> {
        try ensureSessionReady()
        await ensureHeaderSynchronization(options: options)
        
        if headerSubscription == nil {
            try await startHeaderSynchronization(options: options)
        }
        
        guard let latestHeaderInitialResponse,
              headerSubscription != nil else {
            throw Error.sessionNotStarted
        }
        
        let identifier = UUID()
        var capturedContinuation: AsyncThrowingStream<SwiftFulcrum.Response.Result.Blockchain.Headers.SubscribeNotification, Swift.Error>.Continuation!
        let updates = AsyncThrowingStream<SwiftFulcrum.Response.Result.Blockchain.Headers.SubscribeNotification, Swift.Error> { continuation in
            continuation.onTermination = { [weak self] _ in
                guard let self else { return }
                Task { await self.removeHeaderSubscriber(identifier: identifier) }
            }
            capturedContinuation = continuation
        }
        
        guard let continuation = capturedContinuation else {
            throw Error.sessionNotStarted
        }
        
        await registerHeaderSubscriber(identifier: identifier, continuation: continuation)
        
        return Subscription(identifier: identifier,
                            updates: updates,
                            fetchLatestInitialResponse: { [weak session = self] in
            guard let session else { return latestHeaderInitialResponse }
            if let current = await session.readCurrentHeaderInitialResponse() {
                return current
            }
            return latestHeaderInitialResponse
        },
                            checkIsActive: { [weak session = self] in
            guard let session else { return false }
            return await session.isHeaderSubscriberActive(identifier: identifier)
        },
                            cancel: { [weak session = self] in
            guard let session else { return }
            await session.cancelHeaderSubscriber(identifier: identifier)
        },
                            resubscribe: { [weak session = self] in
            guard let session else { return latestHeaderInitialResponse }
            return try await session.resubscribeHeaderSubscription(for: identifier)
        })
    }
}
