// Network+Wallet+FulcrumPool+ServerHealth.swift

import Foundation

extension Network.Wallet.FulcrumPool {
    public actor ServerHealth {
        public enum Condition: String, Sendable {
            case healthy
            case degraded
            case unhealthy
        }
        
        public struct Snapshot: Sendable {
            public let latency: TimeInterval?
            public let condition: Condition
            public let failures: Int
            public let quarantineUntil: Date?
            public let lastOK: Date?
            
            var walletStatus: Network.Wallet.Status {
                switch condition {
                case .healthy:
                    return .online
                case .degraded:
                    return .connecting
                case .unhealthy:
                    return .offline
                }
            }
            
            var nextAttempt: Date { quarantineUntil ?? .distantPast }
            
            init(latency: TimeInterval?, condition: Condition, failures: Int, quarantineUntil: Date?, lastOK: Date?) {
                self.latency = latency
                self.condition = condition
                self.failures = failures
                self.quarantineUntil = quarantineUntil
                self.lastOK = lastOK
            }
        }
        
        private let repository: Storage.Repository.ServerHealth?
        private var cache: [URL: Snapshot] = .init()
        
        public init(repository: Storage.Repository.ServerHealth?) {
            self.repository = repository
        }
        
        public func bootstrap(for url: URL) async throws -> Snapshot? {
            if let cached = cache[url] { return cached }
            guard let repository else { return nil }
            do {
                if let row = try await repository.history(url) {
                    let snapshot = makeSnapshot(from: row)
                    cache[url] = snapshot
                    return snapshot
                }
                return nil
            } catch {
                throw mapError(error, fallbackOperation: "history")
            }
        }
        
        public func recordSuccess(for url: URL, latency: TimeInterval) async throws -> Snapshot {
            let now = Date()
            let snapshot = Snapshot(latency: latency,
                                    condition: .healthy,
                                    failures: 0,
                                    quarantineUntil: nil,
                                    lastOK: now)
            if let repository {
                do {
                    try await repository.recordProbe(url: url, latency: latency, healthy: true)
                    cache[url] = snapshot
                    return snapshot
                } catch {
                    throw mapError(error, fallbackOperation: "recordProbe")
                }
            }
            cache[url] = snapshot
            return snapshot
        }
        
        public func recordFailure(for url: URL, retryAt: Date) async throws -> Snapshot {
            let baseline = cache[url] ?? Snapshot(latency: nil,
                                                  condition: .unhealthy,
                                                  failures: 0,
                                                  quarantineUntil: nil,
                                                  lastOK: nil)
            let failures = baseline.failures + 1
            let until = max(retryAt, Date())
            let snapshot = Snapshot(latency: baseline.latency,
                                    condition: .unhealthy,
                                    failures: failures,
                                    quarantineUntil: until,
                                    lastOK: baseline.lastOK)
            if let repository {
                do {
                    try await repository.recordProbe(url: url, latency: nil, healthy: false)
                } catch {
                    throw mapError(error, fallbackOperation: "recordProbe")
                }
                do {
                    try await repository.quarantine(url, until: until)
                } catch {
                    throw mapError(error, fallbackOperation: "quarantine")
                }
                cache[url] = snapshot
                return snapshot
            }
            cache[url] = snapshot
            return snapshot
        }
        
        private func mapError(_ error: Swift.Error, fallbackOperation: String) -> Network.Wallet.Error {
            if let storageError = error as? Storage.Repository.ServerHealth.Error {
                return .healthRepositoryFailure(storageError)
            }
            return .healthRepositoryFailure(.init(operation: fallbackOperation,
                                                  reason: String(describing: error)))
        }
        
        private func makeSnapshot(from row: Storage.Row.ServerHealth) -> Snapshot {
            let condition = Condition(rawValue: row.status) ?? .unhealthy
            let latency = row.latencyMs.map { $0 / 1000 }
            return Snapshot(latency: latency,
                            condition: condition,
                            failures: row.failures,
                            quarantineUntil: row.quarantineUntil,
                            lastOK: row.lastOK)
        }
    }
}

