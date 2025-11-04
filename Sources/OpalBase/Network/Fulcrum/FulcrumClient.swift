// Network+FulcrumClient.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumClient {
        private let fulcrum: Fulcrum
        public let configuration: Network.Configuration
        
        public init(
            configuration: Network.Configuration,
            metrics: MetricsCollectable? = nil,
            logger: Log.Handler? = nil,
            urlSession: URLSession? = nil
        ) async throws {
            self.configuration = configuration
            
            let reconnectConfiguration = WebSocket.Reconnector.Configuration(
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
                bootstrapServers: configuration.serverURLs.isEmpty ? nil : configuration.serverURLs
            )
            
            self.fulcrum = try await Fulcrum(configuration: fulcrumConfiguration)
            try await self.fulcrum.start()
        }
        
        deinit {
            Task { await fulcrum.stop() }
        }
        
        public func stop() async {
            await fulcrum.stop()
        }
        
        public func reconnect() async throws {
            try await fulcrum.reconnect()
        }
        
        public func request<Result: JSONRPCConvertible>(
            method: SwiftFulcrum.Method,
            responseType: Result.Type = Result.self,
            options: Client.Call.Options = .init()
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
            options: Client.Call.Options = .init()
        ) async throws -> (Initial, AsyncThrowingStream<Notification, Swift.Error>, @Sendable () async -> Void) {
            let response = try await fulcrum.submit(
                method: method,
                initialType: initialType,
                notificationType: notificationType,
                options: options
            )
            guard let stream = response.extractSubscriptionStream() else {
                throw Fulcrum.Error.client(.protocolMismatch("Expected subscription stream for method: \(method)"))
            }
            return stream
        }
    }
}
