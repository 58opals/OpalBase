// Network~Instrumentation.swift

import Foundation

extension Network {
    public enum LogLevel: Sendable {
        case trace
        case debug
        case info
        case notice
        case warning
        case error
        case critical
    }
    
    public protocol LogHandler: Sendable {
        func log(_ level: LogLevel,
                 _ message: @autoclosure () -> String,
                 metadata: [String: String]?,
                 file: String,
                 function: String,
                 line: UInt)
    }
    
    public struct DiagnosticsSnapshot: Sendable, Equatable {
        public let reconnectAttempts: Int
        public let reconnectSuccesses: Int
        public let inflightUnaryCallCount: Int
        public let activeSubscriptionCount: Int
        
        public init(
            reconnectAttempts: Int,
            reconnectSuccesses: Int,
            inflightUnaryCallCount: Int,
            activeSubscriptionCount: Int
        ) {
            self.reconnectAttempts = reconnectAttempts
            self.reconnectSuccesses = reconnectSuccesses
            self.inflightUnaryCallCount = inflightUnaryCallCount
            self.activeSubscriptionCount = activeSubscriptionCount
        }
    }
    
    public struct DiagnosticsSubscription: Sendable, Equatable {
        public let methodPath: String
        public let identifier: String?
        
        public init(methodPath: String, identifier: String?) {
            self.methodPath = methodPath
            self.identifier = identifier
        }
    }
    
    public protocol MetricsCollector: Sendable {
        func didConnect(url: URL, network: Environment) async
        func didDisconnect(url: URL, closeCode: URLSessionWebSocketTask.CloseCode?, reason: String?) async
        func didSend(url: URL, message: URLSessionWebSocketTask.Message) async
        func didReceive(url: URL, message: URLSessionWebSocketTask.Message) async
        func didPing(url: URL, error: Swift.Error?) async
        func didUpdateDiagnostics(url: URL, snapshot: DiagnosticsSnapshot) async
        func didUpdateSubscriptionRegistry(url: URL, subscriptions: [DiagnosticsSubscription]) async
    }
}
