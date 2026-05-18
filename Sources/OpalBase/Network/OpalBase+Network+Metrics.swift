// OpalBase+Network+Metrics.swift

import Foundation
import OpalDiagnostics

extension _OpalBase.Network {
    public struct Metrics: Sendable {
        private let recordDiagnosticsSnapshotHandler: @Sendable (URL, DiagnosticsSnapshot) async -> Void
        private let recordSubscriptionRegistryUpdateHandler: @Sendable (URL, [DiagnosticsSubscription]) async -> Void

        public init(
            recordDiagnosticsSnapshot: @escaping @Sendable (URL, DiagnosticsSnapshot) async -> Void = { _, _ in },
            recordSubscriptionRegistryUpdate: @escaping @Sendable (URL, [DiagnosticsSubscription]) async -> Void = { _, _ in }
        ) {
            self.recordDiagnosticsSnapshotHandler = recordDiagnosticsSnapshot
            self.recordSubscriptionRegistryUpdateHandler = recordSubscriptionRegistryUpdate
        }

        public func recordDiagnosticsSnapshot(url: URL, snapshot: DiagnosticsSnapshot) async {
            OpalDiagnostics.record(
                OpalDiagnostics.Event.networkDiagnosticsSnapshotRecorded,
                category: OpalDiagnostics.Category.network,
                fields: OpalDiagnostics.Field.networkDiagnostics(snapshot: snapshot)
            )
            await recordDiagnosticsSnapshotHandler(url, snapshot)
        }

        public func recordSubscriptionRegistryUpdate(url: URL, subscriptions: [DiagnosticsSubscription]) async {
            OpalDiagnostics.record(
                OpalDiagnostics.Event.networkDiagnosticsSubscriptionsRecorded,
                category: OpalDiagnostics.Category.network,
                fields: OpalDiagnostics.Field.networkSubscriptions(
                    subscriptions: subscriptions,
                    operation: "record_network_diagnostics_subscriptions"
                )
            )
            await recordSubscriptionRegistryUpdateHandler(url, subscriptions)
        }
    }
}
