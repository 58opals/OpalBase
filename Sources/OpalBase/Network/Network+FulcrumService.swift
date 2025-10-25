// Network+FulcrumService.swift

import Foundation
import SwiftFulcrum

extension Network {
    public actor FulcrumService {
        public struct Configuration: Sendable {
            public struct Backoff: Sendable {
                public var initialDelay: TimeInterval
                public var multiplier: Double
                public var maxDelay: TimeInterval
                
                public init(initialDelay: TimeInterval = 1,
                            multiplier: Double = 2,
                            maxDelay: TimeInterval = 32)
                {
                    precondition(initialDelay >= 0, "initialDelay must be non-negative")
                    precondition(multiplier >= 1, "multiplier must be greater than or equal to 1")
                    precondition(maxDelay >= initialDelay, "maxDelay must be greater than or equal to initialDelay")
                    
                    self.initialDelay = initialDelay
                    self.multiplier = multiplier
                    self.maxDelay = maxDelay
                }
            }
            
            public var gateway: Network.Gateway.Configuration
            public var backoff: Backoff
            
            public init(gateway: Network.Gateway.Configuration = .init(),
                        backoff: Backoff = .init())
            {
                var gatewayConfiguration = gateway
                gatewayConfiguration.initialStatus = .offline
                gatewayConfiguration.initialHeaderUpdate = nil
                self.gateway = gatewayConfiguration
                self.backoff = backoff
            }
        }
        
        public enum Error: Swift.Error {
            case noFulcrumInstances
        }
        
        private struct BackoffState {
            let initialDelay: TimeInterval
            let multiplier: Double
            let maxDelay: TimeInterval
            private(set) var currentDelay: TimeInterval
            private(set) var nextAttempt: Date
            
            init(configuration: Configuration.Backoff, now: Date) {
                self.initialDelay = configuration.initialDelay
                self.multiplier = configuration.multiplier
                self.maxDelay = configuration.maxDelay
                self.currentDelay = 0
                self.nextAttempt = now
            }
            
            mutating func registerSuccess(now: Date) {
                currentDelay = 0
                nextAttempt = now
            }
            
            mutating func registerFailure(now: Date) {
                if currentDelay == 0 {
                    currentDelay = initialDelay
                } else {
                    currentDelay = min(maxDelay, currentDelay * multiplier)
                }
                nextAttempt = now.addingTimeInterval(currentDelay)
            }
            
            func isReady(at date: Date) -> Bool {
                date >= nextAttempt
            }
        }
        
        private struct Client {
            let id: UUID
            let fulcrum: SwiftFulcrum.Fulcrum
            let gateway: Network.Gateway
            let node: Network.Wallet.Node
            var isRunning: Bool
            var backoff: BackoffState
        }
        
        private let configuration: Configuration
        private var clients: [Client]
        private var rotationIndex: Int
        
        private var status: Network.Wallet.Status
        private var statusContinuations: [UUID: AsyncStream<Network.Wallet.Status>.Continuation]
        
        public init(fulcrums: [SwiftFulcrum.Fulcrum],
                    configuration: Configuration = .init()) throws
        {
            guard !fulcrums.isEmpty else { throw Error.noFulcrumInstances }
            
            self.configuration = configuration
            self.rotationIndex = 0
            self.status = .offline
            self.statusContinuations = [:]
            
            let now = Date()
            self.clients = fulcrums.map { fulcrum in
                let api = Adapter.SwiftFulcrum.gatewayAPI(fulcrum: fulcrum)
                let gateway = Network.Gateway(api: api, configuration: configuration.gateway)
                return Client(id: UUID(),
                              fulcrum: fulcrum,
                              gateway: gateway,
                              node: .init(fulcrum: fulcrum),
                              isRunning: false,
                              backoff: .init(configuration: configuration.backoff, now: now))
            }
        }
        
        public init(urls: [String], configuration: Configuration = .init()) async throws {
            let fulcrums: [SwiftFulcrum.Fulcrum]
            if urls.isEmpty {
                fulcrums = [try await SwiftFulcrum.Fulcrum()]
            } else {
                fulcrums = try await FulcrumService.buildFulcrums(from: urls)
            }
            try self.init(fulcrums: fulcrums, configuration: configuration)
        }
        
        public var currentStatus: Network.Wallet.Status { status }
        
        public func observeStatus() -> AsyncStream<Network.Wallet.Status> {
            AsyncStream { continuation in
                let identifier = UUID()
                continuation.yield(status)
                statusContinuations[identifier] = continuation
                continuation.onTermination = { _ in
                    Task { await self.removeContinuation(identifier) }
                }
            }
        }
        
        public func getTransaction(for hash: Transaction.Hash) async throws -> Transaction? {
            try await withClient { client in
                try await client.gateway.getTransaction(for: hash)
            }
        }
        
        public func getCurrentMempool(forceRefresh: Bool = false) async throws -> Set<Transaction.Hash> {
            try await withClient { client in
                try await client.gateway.getCurrentMempool(forceRefresh: forceRefresh)
            }
        }
        
        public func refreshMempool() async throws {
            _ = try await getCurrentMempool(forceRefresh: true)
        }
        
        public func submit(_ rawTransaction: Data) async throws -> Transaction.Hash {
            try await withClient { client in
                try await client.gateway.submit(rawTransaction)
            }
        }
        
        public func broadcast(_ transaction: Transaction) async throws -> Transaction.Hash {
            try await withClient { client in
                try await client.gateway.broadcast(transaction)
            }
        }
        
        public func getRawTransaction(for hash: Transaction.Hash) async throws -> Data {
            try await withClient { client in
                try await client.gateway.getRawTransaction(for: hash)
            }
        }
        
        public func getDetailedTransaction(for hash: Transaction.Hash) async throws -> Transaction.Detailed {
            try await withClient { client in
                try await client.gateway.getDetailedTransaction(for: hash)
            }
        }
        
        public func getEstimateFee(targetBlocks: Int) async throws -> Satoshi {
            try await withClient { client in
                try await client.gateway.getEstimateFee(targetBlocks: targetBlocks)
            }
        }
        
        public func getRelayFee() async throws -> Satoshi {
            try await withClient { client in
                try await client.gateway.getRelayFee()
            }
        }
        
        public func getHeader(height: UInt32) async throws -> Network.Gateway.HeaderPayload? {
            try await withClient { client in
                try await client.gateway.getHeader(height: height)
            }
        }
        
        public func pingHeadersTip() async throws {
            _ = try await withClient { client in
                try await client.gateway.pingHeadersTip()
            }
        }
        
        public func balance(for address: Address, includeUnconfirmed: Bool) async throws -> Satoshi {
            try await withClient { client in
                try await client.node.balance(for: address, includeUnconfirmed: includeUnconfirmed)
            }
        }
        
        public func unspentOutputs(for address: Address) async throws -> [Transaction.Output.Unspent] {
            try await withClient { client in
                try await client.node.unspentOutputs(for: address)
            }
        }
        
        public func simpleHistory(for address: Address,
                                  fromHeight: UInt?,
                                  toHeight: UInt?,
                                  includeUnconfirmed: Bool) async throws -> [Transaction.Simple]
        {
            try await withClient { client in
                try await client.node.simpleHistory(for: address,
                                                    fromHeight: fromHeight,
                                                    toHeight: toHeight,
                                                    includeUnconfirmed: includeUnconfirmed)
            }
        }
        
        public func detailedHistory(for address: Address,
                                    fromHeight: UInt?,
                                    toHeight: UInt?,
                                    includeUnconfirmed: Bool) async throws -> [Transaction.Detailed]
        {
            try await withClient { client in
                try await client.node.detailedHistory(for: address,
                                                      fromHeight: fromHeight,
                                                      toHeight: toHeight,
                                                      includeUnconfirmed: includeUnconfirmed)
            }
        }
        
        public func subscribe(to address: Address) async throws -> Network.Wallet.SubscriptionStream {
            try await withClient { client in
                try await client.node.subscribe(to: address)
            }
        }
        
        private func withClient<Value>(
            _ operation: @escaping (Client) async throws -> Value
        ) async throws -> Value {
            var allowWait = true
            var lastConnectionError: Swift.Error?
            
            while true {
                try Task.checkCancellation()
                let now = Date()
                var earliestRetry: Date?
                var attempted = false
                
                for offset in clients.indices {
                    let index = (rotationIndex + offset) % clients.count
                    var client = clients[index]
                    
                    if !client.backoff.isReady(at: now) {
                        earliestRetry = earliestRetry.map { min($0, client.backoff.nextAttempt) } ?? client.backoff.nextAttempt
                        continue
                    }
                    
                    attempted = true
                    
                    do {
                        if !client.isRunning {
                            updateStatus(.connecting)
                            try await client.fulcrum.start()
                            try await client.gateway.pingHeadersTip()
                            await client.gateway.updateHealth(status: .online, lastHeaderAt: Date())
                            client.isRunning = true
                        }
                        
                        let result = try await operation(client)
                        client.backoff.registerSuccess(now: now)
                        clients[index] = client
                        rotationIndex = (index + 1) % max(clients.count, 1)
                        updateStatus(.online)
                        return result
                    } catch {
                        if let cancellation = error as? CancellationError { throw cancellation }
                        
                        if shouldTreatAsConnectionFailure(error) {
                            lastConnectionError = error
                            await client.gateway.updateHealth(status: .offline, lastHeaderAt: nil)
                            await client.fulcrum.stop()
                            client.isRunning = false
                            client.backoff.registerFailure(now: now)
                            clients[index] = client
                            continue
                        }
                        
                        client.backoff.registerSuccess(now: now)
                        clients[index] = client
                        if client.isRunning { updateStatus(.online) }
                        throw error
                    }
                }
                
                if attempted {
                    updateStatus(.offline)
                    if let lastConnectionError { throw lastConnectionError }
                    throw Network.Wallet.Error.noHealthyServer
                }
                
                guard allowWait, let waitDate = earliestRetry else {
                    updateStatus(.offline)
                    if let lastConnectionError { throw lastConnectionError }
                    throw Network.Wallet.Error.noHealthyServer
                }
                
                allowWait = false
                let interval = max(0, waitDate.timeIntervalSinceNow)
                updateStatus(.connecting)
                if interval > 0 {
                    try await sleep(for: interval)
                } else {
                    await Task.yield()
                }
            }
        }
        
        private func shouldTreatAsConnectionFailure(_ error: Swift.Error) -> Bool {
            if error is CancellationError { return false }
            
            if let walletError = error as? Network.Wallet.Error {
                switch walletError {
                case .connectionFailed, .pingFailed, .noHealthyServer:
                    return true
                case .healthRepositoryFailure:
                    return true
                }
            }
            
            if let gatewayError = error as? Network.Gateway.Error {
                switch gatewayError.reason {
                case .transport:
                    return true
                case .poolUnhealthy, .headersStale, .rejected:
                    return false
                }
            }
            
            if let fulcrumError = error as? Fulcrum.Error {
                switch fulcrumError {
                case .transport, .client:
                    return true
                case .rpc, .coding:
                    return false
                }
            }
            
            if let nodeError = error as? Network.Wallet.NodeError {
                switch nodeError.reason {
                case .transport, .coding:
                    return true
                case .rejected, .unknown:
                    return false
                }
            }
            
            return false
        }
        
        private func sleep(for interval: TimeInterval) async throws {
            guard interval > 0 else { return }
            let limit = Double(UInt64.max) / 1_000_000_000.0
            let clamped = min(interval, limit)
            let nanoseconds = UInt64(clamped * 1_000_000_000)
            try await Task.sleep(nanoseconds: nanoseconds)
        }
        
        private func updateStatus(_ newStatus: Network.Wallet.Status) {
            guard status != newStatus else { return }
            status = newStatus
            for continuation in statusContinuations.values {
                continuation.yield(newStatus)
            }
        }
        
        private func removeContinuation(_ identifier: UUID) {
            statusContinuations.removeValue(forKey: identifier)
        }
        
        private static func buildFulcrums(from urls: [String]) async throws -> [SwiftFulcrum.Fulcrum] {
            try await withThrowingTaskGroup(of: (Int, SwiftFulcrum.Fulcrum).self) { group in
                for (index, url) in urls.enumerated() {
                    group.addTask {
                        (index, try await SwiftFulcrum.Fulcrum(url: url))
                    }
                }
                
                var results: [SwiftFulcrum.Fulcrum?] = .init(repeating: nil, count: urls.count)
                for try await (index, fulcrum) in group {
                    results[index] = fulcrum
                }
                
                return results.compactMap { $0 }
            }
        }
    }
}
