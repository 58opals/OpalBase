// Network+Wallet+FulcrumPool+Quarantine.swift

import Foundation
import SwiftFulcrum

extension Network.Wallet.FulcrumPool.PoolState {
    func acquireFulcrum(now: Date = .init()) async throws -> Fulcrum {
        try await refreshHealth(now: now)
        assignRoles(now: now)
        
        let prioritized = prioritizedServerIndices(now: now)
        guard !prioritized.isEmpty else {
            if status != .offline { updateStatus(.offline) }
            throw Network.Wallet.Error.noHealthyServer
        }
        
        for index in prioritized {
            let server = servers[index]
            guard now >= server.nextRetry else { continue }
            
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
                try await markSuccess(at: index, latency: latency, now: now)
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
                    try await markFailure(at: index, now: now)
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
                    try await markFailure(at: index, now: now)
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
    
    func acquireGateway(now: Date = .init()) async throws -> Network.Gateway {
        _ = try await acquireFulcrum(now: now)
        guard let primaryIndex else {
            updateStatus(.offline)
            throw Network.Wallet.Error.noHealthyServer
        }
        if status != .online { updateStatus(.online) }
        return servers[primaryIndex].gateway
    }
    
    func acquireNode(now: Date = .init()) async throws -> Network.Wallet.Node {
        let fulcrum = try await acquireFulcrum(now: now)
        return Network.Wallet.Node(fulcrum: fulcrum)
    }
    
    func reportFailure(now: Date = .init()) async throws {
        assignRoles(now: now)
        guard !servers.isEmpty else {
            updateStatus(.offline)
            throw Network.Wallet.Error.noHealthyServer
        }
        
        guard let index = activeIndex ?? primaryIndex else {
            updateStatus(.offline)
            throw Network.Wallet.Error.noHealthyServer
        }
        
        await servers[index].fulcrum.stop()
        try await markFailure(at: index, now: now)
        activeIndex = primaryIndex
        
        _ = try await acquireFulcrum(now: now)
    }
    
    func reconnect(now: Date = .init()) async throws -> Fulcrum {
        updateStatus(.connecting)
        try await refreshHealth(now: now)
        assignRoles(now: now)
        
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
            try await markSuccess(at: index, latency: latency, now: now)
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
                try await markFailure(at: index, now: now)
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
                try await markFailure(at: index, now: now)
            } catch let repositoryError as Network.Wallet.Error {
                updateStatus(.offline)
                throw repositoryError
            }
            updateStatus(.offline)
            throw Network.Wallet.Error.connectionFailed(error)
        }
    }
    
    private func ping(_ fulcrum: Fulcrum) async throws -> TimeInterval {
        let start = Date()
        do {
            let client = Adapter.SwiftFulcrum.GatewayClient(fulcrum: fulcrum)
            try await client.pingHeadersTip()
            return Date().timeIntervalSince(start)
        } catch {
            throw Network.Wallet.Error.pingFailed(error)
        }
    }
    
    private func markSuccess(at index: Int, latency: TimeInterval, now: Date) async throws {
        var server = servers[index]
        
        if let endpoint = server.endpoint {
            do {
                let snapshot = try await serverHealth.recordSuccess(for: endpoint, latency: latency)
                apply(snapshot, to: &server, adoptStatus: true)
            } catch let repositoryError as Network.Wallet.Error {
                throw repositoryError
            }
        } else {
            server.failureCount = 0
            server.nextRetry = .distantPast
            server.status = .online
            server.lastLatency = latency
            server.lastSuccessAt = now
        }
        
        server.retry.reset(now: now)
        servers[index] = server
        assignRoles(now: now, preferredPrimary: index)
        activeIndex = primaryIndex
        await updateGateway(from: server)
    }
    
    private func markFailure(at index: Int, now: Date) async throws {
        var server = servers[index]
        server.status = .offline
        
        let scheduledRetry = scheduleNextRetry(for: &server, now: now)
        
        if let endpoint = server.endpoint {
            do {
                let snapshot = try await serverHealth.recordFailure(for: endpoint, retryAt: scheduledRetry)
                apply(snapshot, to: &server, adoptStatus: true)
                server.nextRetry = max(server.nextRetry, snapshot.nextAttempt)
                server.failureCount = snapshot.failures
            } catch let repositoryError as Network.Wallet.Error {
                server.failureCount += 1
                servers[index] = server
                assignRoles(now: now)
                activeIndex = primaryIndex
                await updateGateway(from: server)
                throw repositoryError
            }
        } else {
            server.failureCount += 1
        }
        
        servers[index] = server
        assignRoles(now: now)
        activeIndex = primaryIndex
        await updateGateway(from: server)
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
    
    private func updateGateway(from server: Server) async {
        await server.gateway.updateHealth(status: server.status,
                                          lastHeaderAt: server.lastSuccessAt)
    }
    
    func bootstrapPersistentHealth() async throws {
        for index in servers.indices {
            guard let endpoint = servers[index].endpoint else { continue }
            if let snapshot = try await serverHealth.bootstrap(for: endpoint) {
                var server = servers[index]
                apply(snapshot, to: &server, adoptStatus: false)
                servers[index] = server
                await updateGateway(from: server)
            }
        }
    }
    
    private func apply(
        _ snapshot: Network.Wallet.FulcrumPool.ServerHealth.Snapshot,
        to server: inout Server,
        adoptStatus: Bool
    ) {
        server.failureCount = snapshot.failures
        server.nextRetry = snapshot.nextAttempt
        server.lastLatency = snapshot.latency
        server.lastSuccessAt = snapshot.lastOK
        if adoptStatus {
            server.status = snapshot.walletStatus
        }
    }
    
    func refreshHealth(now: Date) async throws {
        let released = try await serverHealth.evictExpiredQuarantine(now: now)
        let releaseSet = Set(released)
        
        for index in servers.indices {
            var server = servers[index]
            guard let endpoint = server.endpoint else { continue }
            if releaseSet.contains(endpoint) {
                server.nextRetry = now
                server.status = .connecting
                server.retry.reset(now: now)
            }
            let snapshot = try await serverHealth.decay(for: endpoint, now: now)
            apply(snapshot, to: &server, adoptStatus: false)
            servers[index] = server
            await updateGateway(from: server)
        }
    }
}
