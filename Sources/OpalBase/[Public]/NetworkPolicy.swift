// NetworkPolicy.swift

import Foundation

public struct NetworkPolicy: Sendable {
    public enum ServerSource: Sendable {
        case manual([URL])
        case automatic
    }
    
    public enum ConnectStrategy: Sendable {
        case eager
        case lazy
    }
    
    public struct Timeouts: Sendable {
        public var connect: TimeInterval
        public var read: TimeInterval
        
        public init(connect: TimeInterval = 10, read: TimeInterval = 30) {
            self.connect = connect
            self.read = read
        }
    }
    
    public struct RetryPolicy: Sendable {
        public var maxAttempts: Int
        public var backoff: TimeInterval
        
        public init(maxAttempts: Int = 3, backoff: TimeInterval = 1) {
            self.maxAttempts = maxAttempts
            self.backoff = backoff
        }
    }
    
    public struct TLSConfig: Sendable {
        public var allowsInvalidCertificates: Bool
        
        public init(allowsInvalidCertificates: Bool = false) {
            self.allowsInvalidCertificates = allowsInvalidCertificates
        }
    }
    
    public enum PrivacyPolicy: Sendable {
        case standard
        case none
    }
    
    public enum TelemetrySink: Sendable {
        case disabled
        case endpoint(URL)
    }
    
    public var serverSource: ServerSource
    public var connectStrategy: ConnectStrategy
    public var timeouts: Timeouts
    public var retryPolicy: RetryPolicy
    public var tls: TLSConfig
    public var privacy: PrivacyPolicy
    public var telemetry: TelemetrySink
    
    public init(serverSource: ServerSource,
                connectStrategy: ConnectStrategy = .eager,
                timeouts: Timeouts = .init(),
                retryPolicy: RetryPolicy = .init(),
                tls: TLSConfig = .init(),
                privacy: PrivacyPolicy = .standard,
                telemetry: TelemetrySink = .disabled) {
        self.serverSource = serverSource
        self.connectStrategy = connectStrategy
        self.timeouts = timeouts
        self.retryPolicy = retryPolicy
        self.tls = tls
        self.privacy = privacy
        self.telemetry = telemetry
    }
}
