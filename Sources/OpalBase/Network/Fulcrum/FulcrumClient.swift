// Network+FulcrumClient.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumClient {
        private let fulcrum: SwiftFulcrum.FulcrumClient
        public let configuration: Network.Configuration
        private var subscriptions: [UUID: any FulcrumSubscription]
        
        public init(
            configuration: Network.Configuration,
            metrics: MetricsCollector? = nil,
            logger: LogClient? = nil,
            isLoggingEnabled: Bool = true,
            urlSession: URLSession? = nil
        ) async throws {
            self.configuration = configuration
            self.subscriptions = .init()
            
            let fulcrumMetrics = metrics.map { FulcrumMetricsAdapter(environment: configuration.network, collector: $0) }
            let fulcrumLogger = logger.map(FulcrumLogHandlerAdapter.init(handler:))
            
            let reconnectConfiguration = SwiftFulcrum.FulcrumClient.Configuration.ReconnectModel(
                maximumReconnectionAttempts: configuration.reconnectConfiguration.maximumAttempts,
                reconnectionDelay: configuration.reconnectConfiguration.initialDelay.totalSeconds,
                maximumDelay: configuration.reconnectConfiguration.maximumDelay.totalSeconds,
                jitterRange: configuration.reconnectConfiguration.jitterMultiplierRange.lowerBound ... configuration.reconnectConfiguration.jitterMultiplierRange.upperBound
            )
            
            let bootstrapServers = configuration.fulcrumBootstrapServers
            let fulcrumConfiguration = SwiftFulcrum.FulcrumClient.Configuration(
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
            
            self.fulcrum = try await SwiftFulcrum.FulcrumClient(url: nil,
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
        
        func request<Result: JSONRPCResponse>(
            method: SwiftFulcrum.FulcrumMethodRequest,
            responseType: Result.Type = Result.self,
            options: SwiftFulcrum.FulcrumClient.CallModel.OptionsModel = .init()
        ) async throws -> Result {
            let response = try await fulcrum.submit(method: method, responseType: responseType, options: options)
            guard let value = response.extractRegularResponse() else {
                throw SwiftFulcrum.FulcrumClient.Error.client(.protocolMismatch("Expected unary response for method: \(method)"))
            }
            return value
        }
        
        func subscribe<Initial: JSONRPCResponse, Notification: JSONRPCResponse>(
            method: SwiftFulcrum.FulcrumMethodRequest,
            initialType: Initial.Type = Initial.self,
            notificationType: Notification.Type = Notification.self,
            options: SwiftFulcrum.FulcrumClient.CallModel.OptionsModel = .init()
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

private struct FulcrumMetricsAdapter: SwiftFulcrum.MetricsClient {
    private let environment: Network.Environment
    private let collector: any Network.MetricsCollector
    
    init(environment: Network.Environment, collector: any Network.MetricsCollector) {
        self.environment = environment
        self.collector = collector
    }
    
    func recordConnect(url: URL, network _: SwiftFulcrum.FulcrumClient.Configuration.NetworkModel) async {
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
    
    func recordDiagnosticsUpdate(url: URL, snapshot: SwiftFulcrum.FulcrumClient.DiagnosticsModel.SnapshotModel) async {
        await collector.recordDiagnosticsSnapshot(url: url, snapshot: .init(snapshot))
    }
    
    func recordSubscriptionRegistryUpdate(url: URL, subscriptions: [SwiftFulcrum.FulcrumClient.DiagnosticsModel.SubscriptionModel]) async {
        await collector.recordSubscriptionRegistryUpdate(url: url, subscriptions: subscriptions.map(Network.DiagnosticsSubscription.init(_:)))
    }
}

private struct FulcrumLogHandlerAdapter: SwiftFulcrum.LogModel.HandlerModel {
    private let handler: any Network.LogClient
    
    init(handler: any Network.LogClient) {
        self.handler = handler
    }
    
    func log(_ level: SwiftFulcrum.LogModel.LevelModel,
             _ message: @autoclosure () -> String,
             metadata: [String : String]?,
             file: String,
             function: String,
             line: UInt) {
        handler.log(.init(level), message(), metadata: metadata, file: file, function: function, line: line)
    }
}
