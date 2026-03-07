// OpalBase+Network+MetricsClient_.swift

import Foundation

extension _OpalBase.Network {
    public protocol MetricsClient: Sendable {
        func recordConnection(url: URL, network: EnvironmentModel) async
        func recordDisconnection(url: URL, closeCode: URLSessionWebSocketTask.CloseCode?, reason: String?) async
        func recordSentMessage(url: URL, message: URLSessionWebSocketTask.Message) async
        func recordReceivedMessage(url: URL, message: URLSessionWebSocketTask.Message) async
        func recordPing(url: URL, error: Swift.Error?) async
        func recordDiagnosticsSnapshot(url: URL, snapshot: DiagnosticsSnapshotModel) async
        func recordSubscriptionRegistryUpdate(url: URL, subscriptions: [DiagnosticsSubscriptionModel]) async
    }
}
