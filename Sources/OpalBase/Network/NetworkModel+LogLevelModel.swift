// NetworkModel~Instrumentation.swift

import Foundation

extension NetworkModel {
    public enum LogLevelModel: Sendable {
        case trace
        case debug
        case info
        case notice
        case warning
        case error
        case critical
    }
    
    public protocol LogClient: Sendable {
        func log(_ level: LogLevelModel,
                 _ message: @autoclosure () -> String,
                 metadata: [String: String]?,
                 file: String,
                 function: String,
                 line: UInt)
    }
    
    public struct DiagnosticsSnapshotModel: Sendable, Equatable {
        public let reconnectionAttemptCount: Int
        public let reconnectSuccesses: Int
        public let inflightUnaryCallCount: Int
        public let activeSubscriptionCount: Int
        
        public init(
            reconnectionAttemptCount: Int,
            reconnectSuccesses: Int,
            inflightUnaryCallCount: Int,
            activeSubscriptionCount: Int
        ) {
            self.reconnectionAttemptCount = reconnectionAttemptCount
            self.reconnectSuccesses = reconnectSuccesses
            self.inflightUnaryCallCount = inflightUnaryCallCount
            self.activeSubscriptionCount = activeSubscriptionCount
        }
    }
    
    public struct DiagnosticsSubscriptionModel: Sendable, Equatable {
        public let methodPath: String
        public let identifier: String?
        
        public init(methodPath: String, identifier: String?) {
            self.methodPath = methodPath
            self.identifier = identifier
        }
    }
    
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
