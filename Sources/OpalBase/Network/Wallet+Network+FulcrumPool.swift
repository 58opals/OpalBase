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
        private var statusContinuations: [UUID: AsyncStream<Wallet.Network.Status>.Continuation] = .init()
        
        public init(urls: [String] = [], maxBackoff: TimeInterval = 64) async throws {
            self.servers = []
            self.maxBackoff = maxBackoff
            self.status = .offline
            
            if urls.isEmpty {
                let fulcrum = try await Fulcrum()
                self.servers = [.init(fulcrum: fulcrum)]
            } else {
                self.servers = try await withThrowingTaskGroup(of: Server.self) { group in
                    for url in urls {
                        group.addTask {
                            let fulcrum = try await Fulcrum(url: url)
                            return Server(fulcrum: fulcrum)
                        }
                    }
                    
                    var builtServers: [Server] = []
                    for try await server in group { builtServers.append(server) }
                    return builtServers
                }
            }
        }
    }
}

extension Wallet.Network.FulcrumPool {
    public var currentStatus: Wallet.Network.Status { status }
    
    private func addContinuation(_ continuation: AsyncStream<Wallet.Network.Status>.Continuation) {
        let identifier = UUID()
        continuation.onTermination = { @Sendable _ in
            Task { await self.removeContinuation(for: identifier) }
        }
        statusContinuations[identifier] = continuation
        
        continuation.yield(status)
    }
    
    private func removeContinuation(for identifier: UUID) {
        statusContinuations.removeValue(forKey: identifier)
    }
    
    func observeStatus() -> AsyncStream<Wallet.Network.Status> {
        AsyncStream { continuation in
            Task { self.addContinuation(continuation) }
        }
    }
    
    private func updateStatus(_ newStatus: Wallet.Network.Status) {
        guard newStatus != status else { return }
        status = newStatus
        for continuation in statusContinuations.values { continuation.yield(newStatus) }
    }
}

extension Wallet.Network.FulcrumPool {
    public func getFulcrum() async throws -> Fulcrum {
        updateStatus(.connecting)
        
        var attempts: Int = 0
        while attempts < servers.count {
            var server = servers[currentIndex]
            if Date() >= server.nextRetry {
                do {
                    if server.status != .online {
                        updateStatus(.connecting)
                        try await server.fulcrum.start()
                        try await ping(server.fulcrum)
                        server.status = .online
                        updateStatus(.online)
                    }
                    server.failureCount = 0
                    server.nextRetry = .distantPast
                    servers[currentIndex] = server
                    
                    updateStatus(.online)
                    return server.fulcrum
                } catch {
                    await server.fulcrum.stop()
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
    
    private func ping(_ fulcrum: Fulcrum) async throws {
        _ = try await fulcrum.submit(method: .blockchain(.headers(.getTip)), responseType: Response.Result.Blockchain.Headers.GetTip.self)
    }
    
    private func markFailure(at index: Int) {
        var server = servers[index]
        server.failureCount += 1
        let backoff = min(pow(2.0, Double(server.failureCount)), maxBackoff)
        server.nextRetry = Date().addingTimeInterval(backoff)
        servers[index] = server
        updateStatus(.offline)
    }
    
    public func reportFailure() {
        markFailure(at: currentIndex)
        currentIndex = (currentIndex + 1) % servers.count
        updateStatus(.connecting)
        
        Task {
            do {
                _ = try await self.getFulcrum()
            } catch {
                updateStatus(.offline)
                throw Wallet.Network.Error.connectionFailed(error)
            }
        }
    }
    
    public func reconnect() async throws -> Fulcrum{
        updateStatus(.connecting)
        
        guard servers.indices.contains(currentIndex) else {
            updateStatus(.offline)
            throw Wallet.Network.Error.noHealthyServer
        }
        
        var server = servers[currentIndex]
        
        server.failureCount = 0
        server.nextRetry = .distantPast
        server.status = .offline
        servers[currentIndex] = server
        
        await server.fulcrum.stop()
        server.status = .online
        servers[currentIndex] = server
        
        updateStatus(.online)
        return server.fulcrum
    }
}
