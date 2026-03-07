// OpalBase+Network+Fulcrum+Client.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public actor Client {
        private let fulcrum: SwiftFulcrum.Client
        public let configuration: OpalBase.Network.Configuration
        private var subscriptions: [UUID: any OpalBase.Network.FulcrumSubscriptionClient]
        
        public init(
            configuration: OpalBase.Network.Configuration,
            metrics: OpalBase.Network.MetricsClient? = nil,
            logger: OpalBase.Network.LogClient? = nil,
            isLoggingEnabled: Bool = true,
            urlSession: URLSession? = nil
        ) async throws {
            self.configuration = configuration
            self.subscriptions = .init()
            
            let fulcrumMetrics = metrics.map { FulcrumMetricsAdapter(environment: configuration.network, collector: $0) }
            let fulcrumLogger: (any SwiftFulcrum.Logging.Adapter)? = logger.map { FulcrumLogHandlerAdapter(handler: $0) }
            
            let reconnectConfiguration = SwiftFulcrum.Client.Configuration.ReconnectPolicy(
                maximumReconnectionAttempts: configuration.reconnectConfiguration.maximumAttempts,
                reconnectionDelay: configuration.reconnectConfiguration.initialDelay.totalSeconds,
                maximumDelay: configuration.reconnectConfiguration.maximumDelay.totalSeconds,
                jitterRange: configuration.reconnectConfiguration.jitterMultiplierRange.lowerBound ... configuration.reconnectConfiguration.jitterMultiplierRange.upperBound
            )
            
            let bootstrapServers = configuration.fulcrumBootstrapServers
            let fulcrumConfiguration = SwiftFulcrum.Client.Configuration(
                reconnect: reconnectConfiguration,
                metrics: fulcrumMetrics,
                logger: fulcrumLogger,
                isLoggingEnabled: isLoggingEnabled,
                urlSession: urlSession,
                connectionTimeout: configuration.connectionTimeout.totalSeconds,
                maximumMessageSize: configuration.maximumMessageSize,
                bootstrapServers: bootstrapServers.isEmpty ? nil : bootstrapServers,
                serverCatalogLoader: configuration.makeFulcrumServerCatalogRepository(),
                network: configuration.network.fulcrumNetwork
            )
            
            self.fulcrum = try await SwiftFulcrum.Client(
                url: nil,
                configuration: fulcrumConfiguration
            )
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
        
        func request<Result: SwiftFulcrum.RPC.JSONRPCResponseAdapter>(
            method: SwiftFulcrum.RPC.Method,
            responseType: Result.Type = Result.self,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> Result {
            let response = try await fulcrum.submit(method: method, responseType: responseType, options: options)
            guard let value = response.extractRegularResponse() else {
                throw SwiftFulcrum.Client.Error.client(.protocolMismatch("Expected unary response for method: \(method)"))
            }
            return value
        }
        
        func subscribe<Initial: SwiftFulcrum.RPC.JSONRPCResponseAdapter, Notification: SwiftFulcrum.RPC.JSONRPCResponseAdapter>(
            method: SwiftFulcrum.RPC.Method,
            initialType: Initial.Type = Initial.self,
            notificationType: Notification.Type = Notification.self,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> (Initial, AsyncThrowingStream<Notification, Swift.Error>, @Sendable () async -> Void) {
            let subscription = OpalBase.Network.FulcrumSubscriptionBoxActor<Initial, Notification>(
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
        
        private func failSubscriptions(_ subscriptions: [any OpalBase.Network.FulcrumSubscriptionClient], error: Swift.Error) async {
            for subscription in subscriptions {
                await subscription.fail(with: error)
            }
        }
    }
}

private struct FulcrumMetricsAdapter: SwiftFulcrum.Metrics.MetricsClient {
    private let environment: OpalBase.Network.EnvironmentModel
    private let collector: any OpalBase.Network.MetricsClient
    
    init(environment: OpalBase.Network.EnvironmentModel, collector: any OpalBase.Network.MetricsClient) {
        self.environment = environment
        self.collector = collector
    }
    
    func recordConnect(url: URL, network _: SwiftFulcrum.Client.Configuration.Network) async {
        await collector.recordConnection(url: url, network: environment)
    }
    
    func recordDisconnect(url: URL, closeCode: URLSessionWebSocketTask.CloseCode?, reason: String?) async {
        await collector.recordDisconnection(url: url, closeCode: closeCode, reason: reason)
    }
    
    func recordSend(url: URL, message: URLSessionWebSocketTask.Message) async {
        await collector.recordSentMessage(url: url, message: message)
    }
    
    func recordReceive(url: URL, message: URLSessionWebSocketTask.Message) async {
        await collector.recordReceivedMessage(url: url, message: message)
    }
    
    func recordPing(url: URL, error: Swift.Error?) async {
        await collector.recordPing(url: url, error: error)
    }
    
    func recordDiagnosticsUpdate(url: URL, snapshot: SwiftFulcrum.Client.Diagnostics.Snapshot) async {
        await collector.recordDiagnosticsSnapshot(url: url, snapshot: .init(snapshot))
    }
    
    func recordSubscriptionRegistryUpdate(url: URL, subscriptions: [SwiftFulcrum.Client.Diagnostics.Subscription]) async {
        await collector.recordSubscriptionRegistryUpdate(url: url, subscriptions: subscriptions.map(OpalBase.Network.DiagnosticsSubscriptionModel.init(_:)))
    }
}

private struct FulcrumLogHandlerAdapter: SwiftFulcrum.Logging.Adapter {
    private let handler: any OpalBase.Network.LogClient
    
    init(handler: any OpalBase.Network.LogClient) {
        self.handler = handler
    }
    
    func log(_ level: SwiftFulcrum.Logging.Level,
             _ message: @autoclosure () -> String,
             metadata: [String : String]?,
             file: String,
             function: String,
             line: UInt) {
        handler.log(.init(level), message(), metadata: metadata, file: file, function: function, line: line)
    }
}
