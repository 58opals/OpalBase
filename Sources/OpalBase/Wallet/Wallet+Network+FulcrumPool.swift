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
        
        private var status: Wallet.Network.Status = .offline
        var statusContinuations: [AsyncStream<Wallet.Network.Status>.Continuation] = .init()
        
        init(urls: [String] = [], maxBackoff: TimeInterval = 64) throws {
            if urls.isEmpty {
                self.servers = [.init(fulcrum: try .init())]
            } else {
                self.servers = try urls.map { url in
                        .init(fulcrum: try .init(url: url))
                }
            }
            
            self.maxBackoff = maxBackoff
            self.status = .offline
        }
    }
}

extension Wallet.Network.FulcrumPool {
    var currentStatus: Wallet.Network.Status { status }
    
    private func addContinuation(_ continuation: AsyncStream<Wallet.Network.Status>.Continuation) {
        statusContinuations.append(continuation)
        continuation.yield(status)
    }
    
    func observeStatus() -> AsyncStream<Wallet.Network.Status> {
        AsyncStream { continuation in
            Task { self.addContinuation(continuation) }
        }
    }
    
    private func updateStatus(_ newStatus: Wallet.Network.Status) {
        guard newStatus != status else { return }
        status = newStatus
        for continuation in statusContinuations { continuation.yield(newStatus) }
    }
}

extension Wallet.Network.FulcrumPool {
    func getFulcrum() async throws -> Fulcrum {
        updateStatus(.connecting)
        
        var attempts: Int = 0
        while attempts < servers.count {
            var server = servers[currentIndex]
            if Date() >= server.nextRetry {
                do {
                    if server.status != .online {
                        updateStatus(.connecting)
                        try await server.fulcrum.start()
                        server.status = .online
                        updateStatus(.online)
                    }
                    server.failureCount = 0
                    server.nextRetry = .distantPast
                    servers[currentIndex] = server
                    
                    updateStatus(.online)
                    return server.fulcrum
                } catch {
                    server.status = .offline
                    servers[currentIndex] = server
                    updateStatus(.offline)
                    markFailure(at: currentIndex)
                }
            }
            
            currentIndex = (currentIndex + 1) % servers.count
            attempts += 1
        }
        
        updateStatus(.offline)
        throw Wallet.Network.Error.noHealthyServer
    }
    
    private func markFailure(at index: Int) {
        var server = servers[index]
        server.failureCount += 1
        let backoff = min(pow(2.0, Double(server.failureCount)), maxBackoff)
        server.nextRetry = Date().addingTimeInterval(backoff)
        servers[index] = server
        updateStatus(.offline)
    }
    
    func reportFailure() {
        markFailure(at: currentIndex)
        updateStatus(.connecting)
    }
}
