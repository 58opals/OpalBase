// Network+Failure.swift

import Foundation

extension Network {
    public struct Failure: Swift.Error, Sendable {
        public enum Reason: Sendable {
            case transport
            case network
            case server(code: Int)
            case cancelled
            case timeout
            case protocolViolation
            case encoding
            case decoding
            case unknown
        }
        
        public let reason: Reason
        public let message: String?
        public let metadata: [String: String]
        
        public init(reason: Reason, message: String? = nil, metadata: [String: String] = .init()) {
            self.reason = reason
            self.message = message
            self.metadata = metadata
        }
    }
}
