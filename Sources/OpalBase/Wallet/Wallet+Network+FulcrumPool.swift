// Wallet+Network+FulcrumPool.swift

import Foundation
import SwiftFulcrum

extension Wallet.Network {
    public actor FulcrumPool {
        struct Server {
            let fulcrum: Fulcrum
            var failureCount: Int = 0
            var nextRetry: Date = .distantPast
            var status: Wallet.Network.Status = .offline
        }
        
        private var servers: [Server]
        private var currentIndex: Int = 0
        private let maxBackoff: TimeInterval
        
        public init(urls: [String] = [], maxBackoff: TimeInterval = 64) throws {
            if urls.isEmpty {
                self.servers = [.init(fulcrum: try .init())]
            } else {
                self.servers = try urls.map { url in
                        .init(fulcrum: try .init(url: url))
                }
            }
            
            self.maxBackoff = maxBackoff
        }
        
        public func getFulcrum() async throws -> Fulcrum {
            var attempts: Int = 0
            while attempts < servers.count {
                var server = servers[currentIndex]
                if Date() >= server.nextRetry {
                    do {
                        if server.status != .online {
                            try await server.fulcrum.start()
                            server.status = .online
                        }
                        server.failureCount = 0
                        server.nextRetry = .distantPast
                        servers[currentIndex] = server
                        return server.fulcrum
                    } catch {
                        server.status = .offline
                        servers[currentIndex] = server
                        markFailure(at: currentIndex)
                    }
                }
                
                currentIndex = (currentIndex + 1) % servers.count
                attempts += 1
            }
            throw Wallet.Network.Error.noHealthyServer
        }
        
        private func markFailure(at index: Int) {
            var server = servers[index]
            server.failureCount += 1
            let backoff = min(pow(2.0, Double(server.failureCount)), maxBackoff)
            server.nextRetry = Date().addingTimeInterval(backoff)
            servers[index] = server
        }
        
        public func reportFailure() {
            markFailure(at: currentIndex)
        }
    }
}
