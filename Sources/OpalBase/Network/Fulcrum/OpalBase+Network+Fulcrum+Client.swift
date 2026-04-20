// OpalBase+Network+Fulcrum+Client.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public actor Client {
        private let fulcrum: SwiftFulcrum.Client
        public let configuration: OpalBase.Network.Configuration
        
        public init(
            configuration: OpalBase.Network.Configuration,
            metrics: OpalBase.Network.Metrics? = nil,
            logger: OpalBase.Network.Logger? = nil,
            isLoggingEnabled: Bool = true
        ) async throws {
            self.configuration = configuration
            
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
                connectionTimeout: configuration.connectTimeout.totalSeconds,
                maximumMessageSize: configuration.maximumMessageSize,
                bootstrapServers: bootstrapServers.isEmpty ? nil : bootstrapServers,
                serverCatalogLoader: configuration.makeFulcrumServerCatalogRepository(),
                network: configuration.network.fulcrumNetwork
            )
            
            self.fulcrum = try await SwiftFulcrum.Client(configuration: fulcrumConfiguration)
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
            try await fulcrum.reconnect()
        }
        
        func request<Result: Decodable & Sendable>(
            method: SwiftFulcrum.RPC.Method,
            responseType: Result.Type = Result.self,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> Result {
            try await fulcrum.request(
                method: method,
                responseType: responseType,
                options: options
            )
        }
        
        func subscribe<Initial: Decodable & Sendable, Notification: Decodable & Sendable>(
            method: SwiftFulcrum.RPC.Method,
            initial: Initial.Type = Initial.self,
            notifications: Notification.Type = Notification.self,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> (Initial, AsyncThrowingStream<Notification, Swift.Error>, @Sendable () async -> Void) {
            let subscription = try await fulcrum.subscribe(
                method: method,
                initial: initial,
                notifications: notifications,
                options: options
            )
            return (
                subscription.initial,
                subscription.updates,
                { await subscription.cancel() }
            )
        }
    }
}

private struct FulcrumMetricsAdapter: SwiftFulcrum.Metrics.MetricsClient {
    private let environment: OpalBase.Network.Environment
    private let collector: OpalBase.Network.Metrics
    
    init(environment: OpalBase.Network.Environment, collector: OpalBase.Network.Metrics) {
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
        await collector.recordSubscriptionRegistryUpdate(url: url, subscriptions: subscriptions.map(OpalBase.Network.DiagnosticsSubscription.init(_:)))
    }
}

private struct FulcrumLogHandlerAdapter: SwiftFulcrum.Logging.Adapter {
    private let handler: OpalBase.Network.Logger
    
    init(handler: OpalBase.Network.Logger) {
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
