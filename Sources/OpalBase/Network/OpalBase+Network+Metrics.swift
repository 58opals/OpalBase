// OpalBase+Network+Metrics.swift

import Foundation

extension _OpalBase.Network {
    public struct Metrics: Sendable {
        private let recordConnectionHandler: @Sendable (URL, Environment) async -> Void
        private let recordDisconnectionHandler: @Sendable (URL, URLSessionWebSocketTask.CloseCode?, String?) async -> Void
        private let recordSentMessageHandler: @Sendable (URL, URLSessionWebSocketTask.Message) async -> Void
        private let recordReceivedMessageHandler: @Sendable (URL, URLSessionWebSocketTask.Message) async -> Void
        private let recordPingHandler: @Sendable (URL, Swift.Error?) async -> Void
        private let recordDiagnosticsSnapshotHandler: @Sendable (URL, DiagnosticsSnapshot) async -> Void
        private let recordSubscriptionRegistryUpdateHandler: @Sendable (URL, [DiagnosticsSubscription]) async -> Void

        public init(
            recordConnection: @escaping @Sendable (URL, Environment) async -> Void = { _, _ in },
            recordDisconnection: @escaping @Sendable (URL, URLSessionWebSocketTask.CloseCode?, String?) async -> Void = { _, _, _ in },
            recordSentMessage: @escaping @Sendable (URL, URLSessionWebSocketTask.Message) async -> Void = { _, _ in },
            recordReceivedMessage: @escaping @Sendable (URL, URLSessionWebSocketTask.Message) async -> Void = { _, _ in },
            recordPing: @escaping @Sendable (URL, Swift.Error?) async -> Void = { _, _ in },
            recordDiagnosticsSnapshot: @escaping @Sendable (URL, DiagnosticsSnapshot) async -> Void = { _, _ in },
            recordSubscriptionRegistryUpdate: @escaping @Sendable (URL, [DiagnosticsSubscription]) async -> Void = { _, _ in }
        ) {
            self.recordConnectionHandler = recordConnection
            self.recordDisconnectionHandler = recordDisconnection
            self.recordSentMessageHandler = recordSentMessage
            self.recordReceivedMessageHandler = recordReceivedMessage
            self.recordPingHandler = recordPing
            self.recordDiagnosticsSnapshotHandler = recordDiagnosticsSnapshot
            self.recordSubscriptionRegistryUpdateHandler = recordSubscriptionRegistryUpdate
        }

        func recordConnection(url: URL, network: Environment) async {
            await recordConnectionHandler(url, network)
        }

        func recordDisconnection(url: URL, closeCode: URLSessionWebSocketTask.CloseCode?, reason: String?) async {
            await recordDisconnectionHandler(url, closeCode, reason)
        }

        func recordSentMessage(url: URL, message: URLSessionWebSocketTask.Message) async {
            await recordSentMessageHandler(url, message)
        }

        func recordReceivedMessage(url: URL, message: URLSessionWebSocketTask.Message) async {
            await recordReceivedMessageHandler(url, message)
        }

        func recordPing(url: URL, error: Swift.Error?) async {
            await recordPingHandler(url, error)
        }

        func recordDiagnosticsSnapshot(url: URL, snapshot: DiagnosticsSnapshot) async {
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.networkDiagnosticsSnapshotRecorded,
                category: OpalBase.Diagnostics.Categories.network,
                fields: OpalBaseDiagnostics.networkDiagnosticsFields(url: url, snapshot: snapshot)
            )
            await recordDiagnosticsSnapshotHandler(url, snapshot)
        }

        func recordSubscriptionRegistryUpdate(url: URL, subscriptions: [DiagnosticsSubscription]) async {
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.networkDiagnosticsSubscriptionsRecorded,
                category: OpalBase.Diagnostics.Categories.network,
                fields: [
                    OpalBaseDiagnostics.operationField("record_network_diagnostics_subscriptions"),
                    OpalBaseDiagnostics.moduleField(),
                    OpalBaseDiagnostics.publicField("active_subscription_count", subscriptions.count)
                ]
            )
            await recordSubscriptionRegistryUpdateHandler(url, subscriptions)
        }
    }
}
