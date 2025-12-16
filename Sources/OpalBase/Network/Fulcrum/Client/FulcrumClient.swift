// Network+FulcrumClient.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumClient {
        private let fulcrum: Fulcrum
        public let configuration: Network.Configuration
        private var subscriptions: [UUID: any FulcrumSubscription]
        
        public init(
            configuration: Network.Configuration,
            metrics: MetricsCollectable? = nil,
            logger: Log.Handler? = nil,
            urlSession: URLSession? = nil
        ) async throws {
            self.configuration = configuration
            self.subscriptions = .init()
            
            let reconnectConfiguration = Fulcrum.Configuration.Reconnect(
                maximumReconnectionAttempts: configuration.reconnect.maximumAttempts,
                reconnectionDelay: configuration.reconnect.initialDelay.totalSeconds,
                maximumDelay: configuration.reconnect.maximumDelay.totalSeconds,
                jitterRange: configuration.reconnect.jitterMultiplierRange.lowerBound ... configuration.reconnect.jitterMultiplierRange.upperBound
            )
            
            let fulcrumConfiguration = Fulcrum.Configuration(
                reconnect: reconnectConfiguration,
                metrics: metrics,
                logger: logger,
                urlSession: urlSession,
                connectionTimeout: configuration.connectionTimeout.totalSeconds,
                maximumMessageSize: configuration.maximumMessageSize,
                bootstrapServers: configuration.serverURLs.isEmpty ? nil : configuration.serverURLs,
                network: configuration.network
            )
            
            self.fulcrum = try await Fulcrum(url: configuration.serverURLs.randomElement()?.absoluteString,
                                             configuration: fulcrumConfiguration)
            try await self.fulcrum.start()
        }
        
        deinit {
            let fulcrumClient = fulcrum
            Task { await fulcrumClient.stop() }
        }
        
        public func stop() async {
            await fulcrum.stop()
        }
        
        public func reconnect() async throws {
            let activeSubscriptions = Array(subscriptions.values)
            for subscription in activeSubscriptions {
                await subscription.prepareForReconnect()
            }
            
            do {
                try await fulcrum.reconnect()
            } catch {
                await failSubscriptions(activeSubscriptions, error: error)
                throw error
            }
            
            for subscription in activeSubscriptions {
                await subscription.resubscribe(using: fulcrum)
            }
        }
        
        public func request<Result: JSONRPCConvertible>(
            method: SwiftFulcrum.Method,
            responseType: Result.Type = Result.self,
            options: Fulcrum.Call.Options = .init()
        ) async throws -> Result {
            let response = try await fulcrum.submit(method: method, responseType: responseType, options: options)
            guard let value = response.extractRegularResponse() else {
                throw Fulcrum.Error.client(.protocolMismatch("Expected unary response for method: \(method)"))
            }
            return value
        }
        
        public func subscribe<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
            method: SwiftFulcrum.Method,
            initialType: Initial.Type = Initial.self,
            notificationType: Notification.Type = Notification.self,
            options: Fulcrum.Call.Options = .init()
        ) async throws -> (Initial, AsyncThrowingStream<Notification, Swift.Error>, @Sendable () async -> Void) {
            let subscription = FulcrumSubscriptionBox<Initial, Notification>(
                method: method,
                options: options
            ) { [self] identifier in
                await self.removeSubscription(withID: identifier)
            }
            
            let initial: Initial
            do {
                initial = try await subscription.establish(using: fulcrum)
            } catch {
                await subscription.fail(with: error)
                throw error
            }
            
            subscriptions[subscription.id] = subscription
            
            let cancel: @Sendable () async -> Void = { [self] in
                await self.cancelSubscription(withID: subscription.id)
            }
            
            return (initial, subscription.stream, cancel)
        }
        
        private func cancelSubscription(withID identifier: UUID) async {
            guard let subscription = subscriptions.removeValue(forKey: identifier) else { return }
            await subscription.cancel()
        }
        
        private func removeSubscription(withID identifier: UUID) async {
            subscriptions.removeValue(forKey: identifier)
        }
        
        private func failSubscriptions(_ subscriptions: [any FulcrumSubscription], error: Swift.Error) async {
            for subscription in subscriptions {
                await subscription.fail(with: error)
            }
        }
    }
}
