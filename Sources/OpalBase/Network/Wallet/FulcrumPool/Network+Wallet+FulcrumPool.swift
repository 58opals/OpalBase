// Network+Wallet+FulcrumPool.swift

import Foundation
import SwiftFulcrum

extension Network.Wallet {
    public actor FulcrumPool {
        public enum Role: Sendable {
            case primary
            case standby
            case candidate
        }
        
        struct Server {
            let fulcrum: Fulcrum
            let endpoint: URL?
            var failureCount: Int
            var nextRetry: Date
            var status: Network.Wallet.Status
            var lastLatency: TimeInterval?
            var lastSuccessAt: Date?
            
            var role: Role
            var retry: Retry
            
            init(fulcrum: Fulcrum, endpoint: URL?, retryConfiguration: Retry.Configuration.Budget) {
                self.fulcrum = fulcrum
                self.endpoint = endpoint
                self.failureCount = 0
                self.nextRetry = .distantPast
                self.status = .offline
                self.lastLatency = nil
                self.lastSuccessAt = nil
                self.role = .candidate
                self.retry = .init(configuration: retryConfiguration)
            }
        }
        
        public let serverHealth: ServerHealth
        private var servers: [Server]
        private let maxBackoff: TimeInterval
        
        private let retryConfiguration: Retry.Configuration
        private var globalRetry: Retry
        
        private var primaryIndex: Int?
        private var standbyIndex: Int?
        private var activeIndex: Int?
        
        private var status: Network.Wallet.Status = .offline
        private var statusContinuations: [UUID: AsyncStream<Network.Wallet.Status>.Continuation] = .init()
        
        public init(
            urls: [String] = [],
            maxBackoff: TimeInterval = 64,
            healthRepository: Storage.Repository.ServerHealth? = nil,
            retryConfiguration: Retry.Configuration = .standard
        ) async throws {
            self.serverHealth = .init(repository: healthRepository)
            self.servers = []
            self.maxBackoff = maxBackoff
            self.retryConfiguration = retryConfiguration
            self.globalRetry = .init(configuration: retryConfiguration.global)
            self.status = .offline
            
            self.primaryIndex = nil
            self.standbyIndex = nil
            self.activeIndex = nil
            
            if urls.isEmpty {
                let fulcrum = try await Fulcrum()
                self.servers = [.init(fulcrum: fulcrum,
                                      endpoint: nil,
                                      retryConfiguration: retryConfiguration.perServer)]
            } else {
                self.servers = try await withThrowingTaskGroup(of: Server.self) { group in
                    for url in urls {
                        group.addTask {
                            let fulcrum = try await Fulcrum(url: url)
                            return Server(fulcrum: fulcrum,
                                          endpoint: .init(string: url),
                                          retryConfiguration: retryConfiguration.perServer)
                        }
                    }
                    
                    var builtServers: [Server] = []
                    for try await server in group { builtServers.append(server) }
                    return builtServers
                }
            }
            
            try await bootstrapPersistentHealth()
            assignRoles()
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
        assignRoles()
        let prioritized = prioritizedServerIndices(now: Date())
        guard !prioritized.isEmpty else {
            if status != .offline { updateStatus(.offline) }
            throw Network.Wallet.Error.noHealthyServer
        }
        
        for index in prioritized {
            let server = servers[index]
            guard Date() >= server.nextRetry else { continue }
            
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
                activeIndex = index
                try await markSuccess(at: index, latency: latency)
                activeIndex = primaryIndex
                guard let primaryIndex else {
                    updateStatus(.offline)
                    throw Network.Wallet.Error.noHealthyServer
                }
                if status != .online { updateStatus(.online) }
                return servers[primaryIndex].fulcrum
            } catch let walletError as Network.Wallet.Error {
                await server.fulcrum.stop()
                var failedServer = servers[index]
                failedServer.status = .offline
                servers[index] = failedServer
                if case .healthRepositoryFailure = walletError {
                    updateStatus(.offline)
                    throw walletError
                }
                do {
                    try await markFailure(at: index)
                } catch let repositoryError as Network.Wallet.Error {
                    updateStatus(.offline)
                    throw repositoryError
                }
            } catch {
                await server.fulcrum.stop()
                var failedServer = servers[index]
                failedServer.status = .offline
                servers[index] = failedServer
                do {
                    try await markFailure(at: index)
                } catch let repositoryError as Network.Wallet.Error {
                    updateStatus(.offline)
                    throw repositoryError
                }
                updateStatus(.offline)
            }
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
        var succeeded = false
        defer {
            if succeeded {
                servers[index] = server
                assignRoles(preferredPrimary: index)
                activeIndex = primaryIndex
            }
        }
        
        let now = Date()
        
        if let endpoint = server.endpoint {
            let snapshot = try await serverHealth.recordSuccess(for: endpoint, latency: latency)
            apply(snapshot, to: &server, adoptStatus: true)
        } else {
            server.failureCount = 0
            server.nextRetry = .distantPast
            server.status = .online
            server.lastLatency = latency
            server.lastSuccessAt = now
        }
        
        server.retry.reset(now: now)
        succeeded = true
    }
    
    private func scheduleNextRetry(for server: inout Server, now: Date) -> Date {
        var delay = max(server.retry.nextDelay(now: now),
                        globalRetry.nextDelay(now: now))
        delay = min(delay, maxBackoff)
        
        let jitterAddition: TimeInterval
        if retryConfiguration.jitter.lowerBound == retryConfiguration.jitter.upperBound {
            jitterAddition = retryConfiguration.jitter.lowerBound
        } else {
            jitterAddition = Double.random(in: retryConfiguration.jitter)
        }
        
        let jittered = min(maxBackoff, delay + max(0, jitterAddition))
        let scheduled = now.addingTimeInterval(jittered)
        server.nextRetry = scheduled
        return scheduled
    }
    
    private func markFailure(at index: Int) async throws {
        var server = servers[index]
        server.status = .offline
        
        defer {
            servers[index] = server
            assignRoles()
            activeIndex = primaryIndex
        }
        server.status = .offline
        
        let now = Date()
        let scheduledRetry = scheduleNextRetry(for: &server, now: now)
        
        if let endpoint = server.endpoint {
            do {
                let snapshot = try await serverHealth.recordFailure(for: endpoint, retryAt: scheduledRetry)
                apply(snapshot, to: &server, adoptStatus: true)
                server.nextRetry = max(server.nextRetry, snapshot.nextAttempt)
                server.failureCount = snapshot.failures
            } catch let repositoryError as Network.Wallet.Error {
                server.failureCount += 1
                throw repositoryError
            }
        } else {
            server.failureCount += 1
        }
    }
    
    public func reportFailure() async throws {
        assignRoles()
        guard !servers.isEmpty else {
            updateStatus(.offline)
            throw Network.Wallet.Error.noHealthyServer
        }
        
        guard let index = activeIndex ?? primaryIndex else {
            updateStatus(.offline)
            throw Network.Wallet.Error.noHealthyServer
        }
        
        await servers[index].fulcrum.stop()
        try await markFailure(at: index)
        activeIndex = primaryIndex
        
        _ = try await acquireFulcrum()
    }
    
    public func reconnect() async throws -> Fulcrum {
        updateStatus(.connecting)
        assignRoles()
        
        guard let index = activeIndex ?? primaryIndex, servers.indices.contains(index) else {
            updateStatus(.offline)
            throw Network.Wallet.Error.noHealthyServer
        }
        
        await servers[index].fulcrum.stop()
        
        do {
            do {
                try await servers[index].fulcrum.start()
            } catch {
                throw Network.Wallet.Error.connectionFailed(error)
            }
            let latency = try await ping(servers[index].fulcrum)
            try await markSuccess(at: index, latency: latency)
            guard let primaryIndex else {
                updateStatus(.offline)
                throw Network.Wallet.Error.noHealthyServer
            }
            updateStatus(.online)
            return servers[primaryIndex].fulcrum
        } catch let walletError as Network.Wallet.Error {
            await servers[index].fulcrum.stop()
            var failedServer = servers[index]
            failedServer.status = .offline
            servers[index] = failedServer
            if case .healthRepositoryFailure = walletError {
                updateStatus(.offline)
                throw walletError
            }
            do {
                try await markFailure(at: index)
            } catch let repositoryError as Network.Wallet.Error {
                updateStatus(.offline)
                throw repositoryError
            }
            updateStatus(.offline)
            throw walletError
        } catch {
            await servers[index].fulcrum.stop()
            var failedServer = servers[index]
            failedServer.status = .offline
            servers[index] = failedServer
            do {
                try await markFailure(at: index)
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
    
    struct RoleMetrics: Sendable {
        let index: Int
        let nextRetry: Date
        let lastLatency: TimeInterval?
    }
    
    static func determineRoles(for metrics: [RoleMetrics],
                               now: Date,
                               preferredPrimary: Int?) -> (primary: Int?, standby: Int?) {
        var available = metrics.filter { now >= $0.nextRetry }
        available.sort { lhs, rhs in
            let lhsLatency = lhs.lastLatency ?? .greatestFiniteMagnitude
            let rhsLatency = rhs.lastLatency ?? .greatestFiniteMagnitude
            if lhsLatency == rhsLatency { return lhs.index < rhs.index }
            return lhsLatency < rhsLatency
        }
        
        if let preferredPrimary,
           let preferredIndex = available.firstIndex(where: { $0.index == preferredPrimary }) {
            let preferred = available.remove(at: preferredIndex)
            available.insert(preferred, at: 0)
        }
        
        var primary = available.first?.index
        var standby = available.dropFirst().first?.index
        
        let deferred = metrics.filter { now < $0.nextRetry }.sorted { lhs, rhs in
            if lhs.nextRetry == rhs.nextRetry {
                let lhsLatency = lhs.lastLatency ?? .greatestFiniteMagnitude
                let rhsLatency = rhs.lastLatency ?? .greatestFiniteMagnitude
                if lhsLatency == rhsLatency { return lhs.index < rhs.index }
                return lhsLatency < rhsLatency
            }
            return lhs.nextRetry < rhs.nextRetry
        }
        
        if primary == nil {
            primary = deferred.first?.index
        }
        
        let orderedCandidates = available + deferred
        if standby == nil {
            standby = orderedCandidates.first(where: { $0.index != primary })?.index
        }
        
        return (primary, standby)
    }
    
    private func assignRoles(now: Date = .init(), preferredPrimary: Int? = nil) {
        guard !servers.isEmpty else {
            primaryIndex = nil
            standbyIndex = nil
            activeIndex = nil
            return
        }
        
        let metrics = servers.enumerated().map { RoleMetrics(index: $0.offset,
                                                             nextRetry: $0.element.nextRetry,
                                                             lastLatency: $0.element.lastLatency) }
        let roles = Self.determineRoles(for: metrics, now: now, preferredPrimary: preferredPrimary)
        primaryIndex = roles.primary
        standbyIndex = roles.standby
        
        for index in servers.indices {
            var server = servers[index]
            switch index {
            case roles.primary:
                server.role = .primary
            case roles.standby:
                server.role = .standby
            default:
                server.role = .candidate
            }
            servers[index] = server
        }
    }
    
    private func prioritizedServerIndices(now: Date = .init()) -> [Int] {
        var ordered: [Int] = []
        if let primaryIndex {
            ordered.append(primaryIndex)
        }
        if let standbyIndex, standbyIndex != primaryIndex {
            ordered.append(standbyIndex)
        }
        
        let excluded = Set(ordered)
        let available = servers.enumerated()
            .filter { now >= $0.element.nextRetry && !excluded.contains($0.offset) }
            .sorted { lhs, rhs in
                let lhsLatency = lhs.element.lastLatency ?? .greatestFiniteMagnitude
                let rhsLatency = rhs.element.lastLatency ?? .greatestFiniteMagnitude
                if lhsLatency == rhsLatency { return lhs.offset < rhs.offset }
                return lhsLatency < rhsLatency
            }
            .map(\.offset)
        
        let deferred = servers.enumerated()
            .filter { now < $0.element.nextRetry && !excluded.contains($0.offset) }
            .sorted { lhs, rhs in
                if lhs.element.nextRetry == rhs.element.nextRetry {
                    let lhsLatency = lhs.element.lastLatency ?? .greatestFiniteMagnitude
                    let rhsLatency = rhs.element.lastLatency ?? .greatestFiniteMagnitude
                    if lhsLatency == rhsLatency { return lhs.offset < rhs.offset }
                    return lhsLatency < rhsLatency
                }
                return lhs.element.nextRetry < rhs.element.nextRetry
            }
            .map(\.offset)
        
        ordered.append(contentsOf: available)
        ordered.append(contentsOf: deferred)
        return ordered
    }
    
    func describeRoles() -> (primary: URL?, standby: URL?) {
        let primary = primaryIndex.flatMap { servers[$0].endpoint }
        let standby = standbyIndex.flatMap { servers[$0].endpoint }
        return (primary, standby)
    }
}
