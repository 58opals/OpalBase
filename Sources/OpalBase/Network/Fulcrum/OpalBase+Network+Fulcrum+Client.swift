// OpalBase+Network+Fulcrum+Client.swift

import Foundation
import OpalDiagnostics
import SwiftFulcrum

extension _OpalBase.Network.Fulcrum {
    public actor Client {
        private static let fallbackDiagnosticsURL = URL(string: "wss://fulcrum.invalid")!
        private static let reconnectAttemptsField = "reconnect_attempts"
        private static let reconnectSuccessesField = "reconnect_successes"
        private static let inflightUnaryCallCountField = "inflight_unary_call_count"
        private static let activeSubscriptionCountField = "active_subscription_count"

        private let fulcrum: SwiftFulcrum.Client
        public let configuration: OpalBase.Network.Configuration
        
        public init(
            configuration: OpalBase.Network.Configuration,
            metrics: OpalBase.Network.Metrics? = nil
        ) async throws {
            self.configuration = configuration
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
                    if let metrics {
                        let snapshot = Self.makeDiagnosticsSnapshotFromRecentRecords()
                        await metrics.recordDiagnosticsSnapshot(url: diagnosticsURL, snapshot: snapshot)
                        await metrics.recordSubscriptionRegistryUpdate(
                            url: diagnosticsURL,
                            subscriptions: []
                        )
                    }
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

        public func makeDiagnosticsSnapshot() async -> OpalBase.Network.DiagnosticsSnapshot {
            let snapshot = Self.makeDiagnosticsSnapshotFromRecentRecords()
            OpalDiagnostics.record(
                OpalDiagnostics.Event.networkDiagnosticsSnapshotRecorded,
                category: OpalDiagnostics.Category.network,
                fields: OpalDiagnostics.Field.networkDiagnostics(snapshot: snapshot)
            )
            return snapshot
        }

        public func listDiagnosticsSubscriptions() async -> [OpalBase.Network.DiagnosticsSubscription] {
            let subscriptions: [OpalBase.Network.DiagnosticsSubscription] = []
            OpalDiagnostics.record(
                OpalDiagnostics.Event.networkDiagnosticsSubscriptionsRecorded,
                category: OpalDiagnostics.Category.network,
                fields: OpalDiagnostics.Field.networkSubscriptions(
                    subscriptions: subscriptions,
                    operation: "list_network_diagnostics_subscriptions"
                )
            )
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

private extension _OpalBase.Network.Fulcrum.Client {
    static func makeDiagnosticsSnapshotFromRecentRecords() -> OpalBase.Network.DiagnosticsSnapshot {
        let records = OpalDiagnostics.recentRecords(
            category: .fulcrum,
            event: .swiftFulcrumClientStateUpdated
        )
        guard let record = records.last else {
            return OpalBase.Network.DiagnosticsSnapshot(
                reconnectionAttemptCount: 0,
                reconnectSuccesses: 0,
                inflightUnaryCallCount: 0,
                activeSubscriptionCount: 0
            )
        }

        return OpalBase.Network.DiagnosticsSnapshot(
            reconnectionAttemptCount: integerField(reconnectAttemptsField, in: record),
            reconnectSuccesses: integerField(reconnectSuccessesField, in: record),
            inflightUnaryCallCount: integerField(inflightUnaryCallCountField, in: record),
            activeSubscriptionCount: integerField(activeSubscriptionCountField, in: record)
        )
    }

    static func integerField(_ name: String, in record: OpalDiagnostics.Record) -> Int {
        guard let value = record.fields.first(where: { $0.name == name })?.value else {
            return 0
        }

        return Int(value) ?? 0
    }
}
