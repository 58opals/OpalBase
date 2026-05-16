// OpalBase+Network+Fulcrum+Client.swift

import Foundation
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public actor Client {
        private static let fallbackDiagnosticsURL = URL(string: "wss://fulcrum.invalid")!

        private let fulcrum: SwiftFulcrum.Client
        private let isLoggingEnabled: Bool
        public let configuration: OpalBase.Network.Configuration
        private var diagnosticsURL: URL {
            configuration.serverURLs.first ?? Self.fallbackDiagnosticsURL
        }
        
        public init(
            configuration: OpalBase.Network.Configuration,
            metrics: OpalBase.Network.Metrics? = nil,
            logger: OpalBase.Network.Logger? = nil,
            isLoggingEnabled: Bool = true
        ) async throws {
            self.configuration = configuration
            self.isLoggingEnabled = isLoggingEnabled
            _ = logger
            let diagnosticsURL = configuration.serverURLs.first ?? Self.fallbackDiagnosticsURL
            
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
            
            self.fulcrum = try await OpalBase.Diagnostics.withTraceID {
                do {
                    let fulcrum = try await SwiftFulcrum.Client(configuration: fulcrumConfiguration)
                    try await fulcrum.start()
                    if isLoggingEnabled {
                        OpalBaseDiagnostics.record(
                            OpalBase.Diagnostics.Events.networkFulcrumClientStarted,
                            category: OpalBase.Diagnostics.Categories.network,
                            fields: [
                                OpalBaseDiagnostics.operationField("fulcrum_client_start"),
                                OpalBaseDiagnostics.moduleField(),
                                OpalBaseDiagnostics.networkField(configuration.network)
                            ]
                        )
                    }
                    if isLoggingEnabled, let metrics {
                        let snapshot = OpalBase.Network.DiagnosticsSnapshot(await fulcrum.makeDiagnosticsSnapshot())
                        await metrics.recordDiagnosticsSnapshot(url: diagnosticsURL, snapshot: snapshot)
                        await metrics.recordSubscriptionRegistryUpdate(
                            url: diagnosticsURL,
                            subscriptions: await fulcrum.listSubscriptions().map(OpalBase.Network.DiagnosticsSubscription.init)
                        )
                    }
                    return fulcrum
                } catch {
                    if isLoggingEnabled {
                        OpalBaseDiagnostics.record(
                            OpalBase.Diagnostics.Events.networkFulcrumClientFailed,
                            category: OpalBase.Diagnostics.Categories.network,
                            fields: [
                                OpalBaseDiagnostics.operationField("fulcrum_client_start"),
                                OpalBaseDiagnostics.moduleField(),
                                OpalBaseDiagnostics.networkField(configuration.network)
                            ] + OpalBaseDiagnostics.errorFields(for: error)
                        )
                    }
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

        public func makeDiagnosticsSnapshot() async -> OpalBase.Network.DiagnosticsSnapshot {
            let snapshot = OpalBase.Network.DiagnosticsSnapshot(await fulcrum.makeDiagnosticsSnapshot())
            if isLoggingEnabled {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.networkDiagnosticsSnapshotRecorded,
                    category: OpalBase.Diagnostics.Categories.network,
                    fields: OpalBaseDiagnostics.networkDiagnosticsFields(snapshot: snapshot)
                )
            }
            return snapshot
        }

        public func listDiagnosticsSubscriptions() async -> [OpalBase.Network.DiagnosticsSubscription] {
            let subscriptions = await fulcrum.listSubscriptions().map(OpalBase.Network.DiagnosticsSubscription.init)
            if isLoggingEnabled {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.networkDiagnosticsSubscriptionsRecorded,
                    category: OpalBase.Diagnostics.Categories.network,
                    fields: OpalBaseDiagnostics.networkSubscriptionFields(
                        subscriptions: subscriptions,
                        operation: "list_network_diagnostics_subscriptions"
                    )
                )
            }
            return subscriptions
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
