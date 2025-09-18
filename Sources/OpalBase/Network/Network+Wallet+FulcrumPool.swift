// Network+Wallet+FulcrumPool.swift

import Foundation
import SwiftFulcrum

extension Network.Wallet {
    public actor FulcrumPool {
        struct Server {
            let fulcrum: Fulcrum
            let endpoint: URL?
            var failureCount: Int
            var nextRetry: Date
            var status: Network.Wallet.Status
            var lastLatency: TimeInterval?
            var lastSuccessAt: Date?
            
            init(fulcrum: Fulcrum, endpoint: URL?) {
                self.fulcrum = fulcrum
                self.endpoint = endpoint
                self.failureCount = 0
                self.nextRetry = .distantPast
                self.status = .offline
                self.lastLatency = nil
                self.lastSuccessAt = nil
            }
        }
        
        public let serverHealth: ServerHealth
        private var servers: [Server]
        private var currentIndex: Int = 0
        private let maxBackoff: TimeInterval
        
        private var status: Network.Wallet.Status = .offline
        private var statusContinuations: [UUID: AsyncStream<Network.Wallet.Status>.Continuation] = .init()
        
        public init(urls: [String] = [],
                    maxBackoff: TimeInterval = 64,
                    healthRepository: Storage.Repository.ServerHealth? = nil) async throws {
            self.serverHealth = .init(repository: healthRepository)
            self.servers = []
            self.maxBackoff = maxBackoff
            self.status = .offline
            
            if urls.isEmpty {
                let fulcrum = try await Fulcrum()
                self.servers = [.init(fulcrum: fulcrum, endpoint: nil)]
            } else {
                self.servers = try await withThrowingTaskGroup(of: Server.self) { group in
                    for url in urls {
                        group.addTask {
                            let fulcrum = try await Fulcrum(url: url)
                            return Server(fulcrum: fulcrum, endpoint: .init(string: url))
                        }
                    }
                    
                    var builtServers: [Server] = []
                    for try await server in group { builtServers.append(server) }
                    return builtServers
                }
            }
            
            try await bootstrapPersistentHealth()
            updatePreferredIndex()
        }
    }
}

extension Network.Wallet.FulcrumPool {
    public var currentStatus: Network.Wallet.Status { status }
    
    private func addContinuation(_ continuation: AsyncStream<Network.Wallet.Status>.Continuation) {
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
    
    func observeStatus() -> AsyncStream<Network.Wallet.Status> {
        AsyncStream { continuation in
            Task { self.addContinuation(continuation) }
        }
    }
    
    private func updateStatus(_ newStatus: Network.Wallet.Status) {
        guard newStatus != status else { return }
        status = newStatus
        for continuation in statusContinuations.values { continuation.yield(newStatus) }
    }
}

extension Network.Wallet.FulcrumPool {
    public func acquireFulcrum() async throws -> Fulcrum {
        updatePreferredIndex()
        var attempts: Int = 0
        while attempts < servers.count {
            let server = servers[currentIndex]
            if Date() >= server.nextRetry {
                do {
                    if server.status != .online {
                        updateStatus(.connecting)
                        do {
                            try await server.fulcrum.start()
                        } catch {
                            throw Network.Wallet.Error.connectionFailed(error)
                        }
                    }
                    
                    let latency = try await ping(server.fulcrum)
                    try await markSuccess(at: currentIndex, latency: latency)
                    if status != .online { updateStatus(.online) }
                    return servers[currentIndex].fulcrum
                } catch let walletError as Network.Wallet.Error {
                    await server.fulcrum.stop()
                    var failedServer = servers[currentIndex]
                    failedServer.status = .offline
                    servers[currentIndex] = failedServer
                    if case .healthRepositoryFailure = walletError {
                        updateStatus(.offline)
                        throw walletError
                    }
                    do {
                        try await markFailure(at: currentIndex)
                    } catch let repositoryError as Network.Wallet.Error {
                        updateStatus(.offline)
                        throw repositoryError
                    }
                } catch {
                    await server.fulcrum.stop()
                    var failedServer = servers[currentIndex]
                    failedServer.status = .offline
                    servers[currentIndex] = failedServer
                    do {
                        try await markFailure(at: currentIndex)
                    } catch let repositoryError as Network.Wallet.Error {
                        updateStatus(.offline)
                        throw repositoryError
                    }
                    updateStatus(.offline)
                }
            }
            
            currentIndex = (currentIndex + 1) % servers.count
            attempts += 1
        }
        
        if status != .offline { updateStatus(.offline) }
        throw Network.Wallet.Error.noHealthyServer
    }
    
    private func ping(_ fulcrum: Fulcrum) async throws -> TimeInterval {
        let start = Date()
        do {
            _ = try await fulcrum.submit(method: .blockchain(.headers(.getTip)),
                                         responseType: Response.Result.Blockchain.Headers.GetTip.self)
            return Date().timeIntervalSince(start)
        } catch {
            throw Network.Wallet.Error.pingFailed(error)
        }
    }
    
    private func markSuccess(at index: Int, latency: TimeInterval) async throws {
        var server = servers[index]
        defer {
            servers[index] = server
            updatePreferredIndex()
        }
        
        if let endpoint = server.endpoint {
            let snapshot = try await serverHealth.recordSuccess(for: endpoint, latency: latency)
            apply(snapshot, to: &server, adoptStatus: true)
        } else {
            server.failureCount = 0
            server.nextRetry = .distantPast
            server.status = .online
            server.lastLatency = latency
            server.lastSuccessAt = Date()
        }
    }
    
    private func markFailure(at index: Int) async throws {
        var server = servers[index]
        defer {
            servers[index] = server
            updatePreferredIndex()
        }
        server.status = .offline
        
        if let endpoint = server.endpoint {
            do {
                let snapshot = try await serverHealth.recordFailure(for: endpoint, maxBackoff: maxBackoff)
                apply(snapshot, to: &server, adoptStatus: true)
            } catch let repositoryError as Network.Wallet.Error {
                server.failureCount += 1
                let backoff = min(pow(2.0, Double(server.failureCount)), maxBackoff)
                server.nextRetry = Date().addingTimeInterval(backoff)
                throw repositoryError
            }
        } else {
            server.failureCount += 1
            let backoff = min(pow(2.0, Double(server.failureCount)), maxBackoff)
            server.nextRetry = Date().addingTimeInterval(backoff)
        }
    }
    
    public func reportFailure() async throws {
        try await markFailure(at: currentIndex)
        currentIndex = (currentIndex + 1) % servers.count
        
        _ = try await acquireFulcrum()
    }
    
    public func reconnect() async throws -> Fulcrum {
        updateStatus(.connecting)
        guard servers.indices.contains(currentIndex) else {
            updateStatus(.offline)
            throw Network.Wallet.Error.noHealthyServer
        }
        
        await servers[currentIndex].fulcrum.stop()
        
        do {
            do {
                try await servers[currentIndex].fulcrum.start()
            } catch {
                throw Network.Wallet.Error.connectionFailed(error)
            }
            let latency = try await ping(servers[currentIndex].fulcrum)
            try await markSuccess(at: currentIndex, latency: latency)
            updateStatus(.online)
            return servers[currentIndex].fulcrum
        } catch let walletError as Network.Wallet.Error {
            await servers[currentIndex].fulcrum.stop()
            var failedServer = servers[currentIndex]
            failedServer.status = .offline
            servers[currentIndex] = failedServer
            if case .healthRepositoryFailure = walletError {
                updateStatus(.offline)
                throw walletError
            }
            do {
                try await markFailure(at: currentIndex)
            } catch let repositoryError as Network.Wallet.Error {
                updateStatus(.offline)
                throw repositoryError
            }
            updateStatus(.offline)
            throw walletError
        } catch {
            await servers[currentIndex].fulcrum.stop()
            var failedServer = servers[currentIndex]
            failedServer.status = .offline
            servers[currentIndex] = failedServer
            do {
                try await markFailure(at: currentIndex)
            } catch let repositoryError as Network.Wallet.Error {
                updateStatus(.offline)
                throw repositoryError
            }
            updateStatus(.offline)
            throw Network.Wallet.Error.connectionFailed(error)
        }
    }
    
    private func bootstrapPersistentHealth() async throws {
        for index in servers.indices {
            guard let endpoint = servers[index].endpoint else { continue }
            if let snapshot = try await serverHealth.bootstrap(for: endpoint) {
                var server = servers[index]
                apply(snapshot, to: &server, adoptStatus: false)
                servers[index] = server
            }
        }
    }
    
    private func apply(_ snapshot: ServerHealth.Snapshot, to server: inout Server, adoptStatus: Bool) {
        server.failureCount = snapshot.failures
        server.nextRetry = snapshot.nextAttempt
        server.lastLatency = snapshot.latency
        server.lastSuccessAt = snapshot.lastOK
        if adoptStatus {
            server.status = snapshot.walletStatus
        }
    }
    
    private func updatePreferredIndex(now: Date = .init()) {
        guard !servers.isEmpty else { return }
        
        let available = servers.enumerated().filter { now >= $0.element.nextRetry }
        if let best = available.min(by: { lhs, rhs in
            let lhsLatency = lhs.element.lastLatency ?? .greatestFiniteMagnitude
            let rhsLatency = rhs.element.lastLatency ?? .greatestFiniteMagnitude
            if lhsLatency == rhsLatency { return lhs.offset < rhs.offset }
            return lhsLatency < rhsLatency
        }) {
            currentIndex = best.offset
            return
        }
        
        if let soonest = servers.enumerated().min(by: { $0.element.nextRetry < $1.element.nextRetry }) {
            currentIndex = soonest.offset
        }
    }
}
