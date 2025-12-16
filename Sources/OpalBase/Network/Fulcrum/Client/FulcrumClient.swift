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
            metrics: MetricsCollector? = nil,
            logger: LogHandler? = nil,
            urlSession: URLSession? = nil
        ) async throws {
            self.configuration = configuration
            self.subscriptions = .init()
            
            let fulcrumMetrics = metrics.map { FulcrumMetricsAdapter(collector: $0) }
            let fulcrumLogger = logger.map(FulcrumLogHandlerAdapter.init(handler:))
            
            let reconnectConfiguration = Fulcrum.Configuration.Reconnect(
                maximumReconnectionAttempts: configuration.reconnect.maximumAttempts,
                reconnectionDelay: configuration.reconnect.initialDelay.totalSeconds,
                maximumDelay: configuration.reconnect.maximumDelay.totalSeconds,
                jitterRange: configuration.reconnect.jitterMultiplierRange.lowerBound ... configuration.reconnect.jitterMultiplierRange.upperBound
            )
            
            let fulcrumConfiguration = Fulcrum.Configuration(
                reconnect: reconnectConfiguration,
                metrics: fulcrumMetrics,
                logger: fulcrumLogger,
                urlSession: urlSession,
                connectionTimeout: configuration.connectionTimeout.totalSeconds,
                maximumMessageSize: configuration.maximumMessageSize,
                bootstrapServers: configuration.serverURLs.isEmpty ? nil : configuration.serverURLs,
                network: configuration.network.fulcrumNetwork
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
        
        func request<Result: JSONRPCConvertible>(
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
        
        func subscribe<Initial: JSONRPCConvertible, Notification: JSONRPCConvertible>(
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

private struct FulcrumMetricsAdapter: SwiftFulcrum.MetricsCollectable {
    private let collector: any Network.MetricsCollector
    
    init(collector: any Network.MetricsCollector) {
        self.collector = collector
    }
    
    func didConnect(url: URL, network: Fulcrum.Configuration.Network) async {
        await collector.didConnect(url: url, network: .init(network))
    }
    
    func didDisconnect(url: URL, closeCode: URLSessionWebSocketTask.CloseCode?, reason: String?) async {
        await collector.didDisconnect(url: url, closeCode: closeCode, reason: reason)
    }
    
    func didSend(url: URL, message: URLSessionWebSocketTask.Message) async {
        await collector.didSend(url: url, message: message)
    }
    
    func didReceive(url: URL, message: URLSessionWebSocketTask.Message) async {
        await collector.didReceive(url: url, message: message)
    }
    
    func didPing(url: URL, error: Swift.Error?) async {
        await collector.didPing(url: url, error: error)
    }
    
    func didUpdateDiagnostics(url: URL, snapshot: Fulcrum.Diagnostics.Snapshot) async {
        await collector.didUpdateDiagnostics(url: url, snapshot: .init(snapshot))
    }
    
    func didUpdateSubscriptionRegistry(url: URL, subscriptions: [Fulcrum.Diagnostics.Subscription]) async {
        await collector.didUpdateSubscriptionRegistry(url: url, subscriptions: subscriptions.map(Network.DiagnosticsSubscription.init(_:)))
    }
}

private struct FulcrumLogHandlerAdapter: SwiftFulcrum.Log.Handler {
    private let handler: any Network.LogHandler
    
    init(handler: any Network.LogHandler) {
        self.handler = handler
    }
    
    func log(_ level: SwiftFulcrum.Log.Level,
             _ message: @autoclosure () -> String,
             metadata: [String : String]?,
             file: String,
             function: String,
             line: UInt) {
        handler.log(.init(level), message(), metadata: metadata, file: file, function: function, line: line)
    }
}
