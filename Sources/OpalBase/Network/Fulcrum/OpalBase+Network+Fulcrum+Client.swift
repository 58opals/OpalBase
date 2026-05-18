// OpalBase+Network+Fulcrum+Client.swift

import OpalDiagnostics
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public actor Client {
        private let fulcrum: SwiftFulcrum.Client
        public let configuration: OpalBase.Network.Configuration
        
        public init(
            configuration: OpalBase.Network.Configuration
        ) async throws {
            self.configuration = configuration
            
            let reconnectConfiguration = SwiftFulcrum.Client.Configuration.ReconnectPolicy(
                maximumReconnectionAttempts: configuration.reconnectConfiguration.maximumAttempts,
                reconnectionDelay: configuration.reconnectConfiguration.initialDelay.totalSeconds,
                maximumDelay: configuration.reconnectConfiguration.maximumDelay.totalSeconds,
                jitterRange: configuration.reconnectConfiguration.jitterMultiplierRange.lowerBound ... configuration.reconnectConfiguration.jitterMultiplierRange.upperBound
            )
            
            let bootstrapServers = configuration.fulcrumBootstrapServers
            let fulcrumConfiguration = SwiftFulcrum.Client.Configuration(
                reconnect: reconnectConfiguration,
                connectionTimeout: configuration.connectTimeout.totalSeconds,
                maximumMessageSize: configuration.maximumMessageSize,
                bootstrapServers: bootstrapServers.isEmpty ? nil : bootstrapServers,
                serverCatalogLoader: configuration.makeFulcrumServerCatalogRepository(),
                network: configuration.network.fulcrumNetwork
            )
            
            self.fulcrum = try await OpalDiagnostics.withTraceID {
                do {
                    let fulcrum = try await SwiftFulcrum.Client(configuration: fulcrumConfiguration)
                    try await fulcrum.start()
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.networkFulcrumClientStarted,
                        category: OpalDiagnostics.Category.network,
                        fields: [
                            OpalDiagnostics.Field.operation("fulcrum_client_start"),
                            OpalDiagnostics.Field.module(),
                            OpalDiagnostics.Field.network(configuration.network)
                        ]
                    )
                    return fulcrum
                } catch {
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.networkFulcrumClientFailed,
                        category: OpalDiagnostics.Category.network,
                        fields: [
                            OpalDiagnostics.Field.operation("fulcrum_client_start"),
                            OpalDiagnostics.Field.module(),
                            OpalDiagnostics.Field.network(configuration.network)
                        ] + OpalDiagnostics.Field.errorFields(for: error)
                    )
                    throw error
                }
            }
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
            _ endpoint: SwiftFulcrum.API.Request<Result>,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> Result {
            try await fulcrum.request(
                endpoint,
                options: options
            )
        }
        
        func subscribe<Initial: Decodable & Sendable, Notification: Decodable & Sendable>(
            _ endpoint: SwiftFulcrum.API.Subscription<Initial, Notification>,
            options: SwiftFulcrum.Client.Call.Options = .init()
        ) async throws -> (Initial, AsyncThrowingStream<Notification, Swift.Error>, @Sendable () async -> Void) {
            let subscription = try await fulcrum.subscribe(
                endpoint,
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
