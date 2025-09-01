// Network+Session+Fulcrum.swift

import Foundation

extension Network.Session {
    public actor Fulcrum {
        public typealias Handshaker = @Sendable () async throws -> Void
        public typealias Pinger = @Sendable () async throws -> Void
        
        private let url: URL
        private let policy: NetworkPolicy
        private let handshaker: Handshaker
        private let pinger: Pinger
        private var heartbeat: Task<Void, Never>?
        
        public init(url: URL, policy: NetworkPolicy, handshaker: @escaping Handshaker, pinger: @escaping Pinger) {
            self.url = url
            self.policy = policy
            self.handshaker = handshaker
            self.pinger = pinger
        }
        
        public func connect() async throws {
            try enforceTLS()
            do {
                try await handshaker()
            } catch {
                throw Error.handshakeFailed(error)
            }
            startHeartbeat()
        }
        
        public func disconnect() {
            heartbeat?.cancel()
            heartbeat = nil
        }
        
        private func enforceTLS() throws {
            guard policy.tls.allowsInvalidCertificates || url.scheme == "wss" else {
                throw Error.tlsRequired
            }
        }
        
        private func startHeartbeat() {
            heartbeat?.cancel()
            heartbeat = Task { [pinger] in
                let base: TimeInterval = 1
                var backoff = base
                let maxBackoff: TimeInterval = 60
                while !Task.isCancelled {
                    do {
                        try await pinger()
                        backoff = base
                        try? await Task.sleep(for: .seconds(15))
                    } catch {
                        let delay = min(maxBackoff, Double.random(in: base...(backoff * 3)))
                        backoff = delay
                        try? await Task.sleep(for: .seconds(delay))
                    }
                }
            }
        }
    }
}

extension Network.Session.Fulcrum {
    public enum Error: Swift.Error, Sendable {
        case tlsRequired
        case handshakeFailed(Swift.Error)
    }
}

extension Network.Session.Fulcrum.Error: Equatable {
    public static func == (lhs: Network.Session.Fulcrum.Error, rhs: Network.Session.Fulcrum.Error) -> Bool {
        lhs.localizedDescription == rhs.localizedDescription
    }
}
