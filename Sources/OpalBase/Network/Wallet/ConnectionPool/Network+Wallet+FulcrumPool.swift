// Network+Wallet+FulcrumPool.swift

import Foundation
import SwiftFulcrum

extension Network.Wallet {
    public struct FulcrumPool: Sendable {
        typealias FulcrumFactory = @Sendable (_ endpoint: String?) async throws -> Fulcrum
        private let state: PoolState
        
        public init(
            urls: [String] = [],
            maxBackoff: TimeInterval = 64,
            healthRepository: Storage.Repository.ServerHealth? = nil,
            retryConfiguration: Retry.Configuration = .standard,
            gatewayConfiguration: Network.Gateway.Configuration = .init()
        ) async throws {
            try await self.init(urls: urls,
                                maxBackoff: maxBackoff,
                                healthRepository: healthRepository,
                                retryConfiguration: retryConfiguration,
                                gatewayConfiguration: gatewayConfiguration,
                                makeFulcrum: Self.liveFulcrumFactory)
        }
        
        init(
            urls: [String],
            maxBackoff: TimeInterval,
            healthRepository: Storage.Repository.ServerHealth?,
            retryConfiguration: Retry.Configuration,
            gatewayConfiguration: Network.Gateway.Configuration,
            makeFulcrum: @escaping FulcrumFactory
        ) async throws {
            self.state = try await PoolState(urls: urls,
                                             maxBackoff: maxBackoff,
                                             healthRepository: healthRepository,
                                             retryConfiguration: retryConfiguration,
                                             gatewayConfiguration: gatewayConfiguration,
                                             makeFulcrum: makeFulcrum)
        }
        
        public var currentStatus: Network.Wallet.Status {
            get async { await state.currentStatus }
        }
        
        public func observeStatus() async -> AsyncStream<Network.Wallet.Status> {
            await state.observeStatus()
        }
        
        public func acquireFulcrum() async throws -> Fulcrum {
            try await state.acquireFulcrum()
        }
        
        public func acquireGateway() async throws -> Network.Gateway {
            try await state.acquireGateway()
        }
        
        public func acquireNode() async throws -> Network.Wallet.Node {
            try await state.acquireNode()
        }
        
        public func reportFailure() async throws {
            try await state.reportFailure()
        }
        
        public func reconnect() async throws -> Fulcrum {
            try await state.reconnect()
        }
        
        public func describeRoles() async -> (primary: URL?, standby: URL?) {
            await state.describeRoles()
        }
        
        internal var stateForTesting: PoolState { state }
    }
}

extension Network.Wallet.FulcrumPool {
    static let liveFulcrumFactory: FulcrumFactory = { endpoint in
        if let endpoint {
            return try await Fulcrum(url: endpoint)
        }
        return try await Fulcrum()
    }
}

extension Network.Wallet.FulcrumPool {
    actor PoolState {
        enum Role: Sendable {
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
            
            let api: Network.Gateway.API
            let gateway: Network.Gateway
            
            init(fulcrum: Fulcrum,
                 endpoint: URL?,
                 retryConfiguration: Retry.Configuration.Budget,
                 gatewayConfiguration: Network.Gateway.Configuration)
            {
                self.fulcrum = fulcrum
                self.endpoint = endpoint
                self.failureCount = 0
                self.nextRetry = .distantPast
                self.status = .offline
                self.lastLatency = nil
                self.lastSuccessAt = nil
                self.role = .candidate
                self.retry = .init(configuration: retryConfiguration)
                var configuration = gatewayConfiguration
                configuration.initialStatus = .offline
                configuration.initialHeaderUpdate = nil
                let api = Adapter.SwiftFulcrum.gatewayAPI(fulcrum: fulcrum)
                self.api = api
                self.gateway = .init(api: api, configuration: configuration)
            }
        }
        
        let serverHealth: ServerHealth
        var servers: [Server]
        let maxBackoff: TimeInterval
        
        let retryConfiguration: Retry.Configuration
        var globalRetry: Retry
        
        var primaryIndex: Int?
        var standbyIndex: Int?
        var activeIndex: Int?
        var status: Network.Wallet.Status
        private var statusContinuations: [UUID: AsyncStream<Network.Wallet.Status>.Continuation]
        
        init(urls: [String],
             maxBackoff: TimeInterval,
             healthRepository: Storage.Repository.ServerHealth?,
             retryConfiguration: Retry.Configuration,
             gatewayConfiguration: Network.Gateway.Configuration,
             makeFulcrum: @escaping FulcrumFactory) async throws
        {
            self.serverHealth = .init(repository: healthRepository)
            self.servers = []
            self.maxBackoff = maxBackoff
            self.retryConfiguration = retryConfiguration
            self.globalRetry = .init(configuration: retryConfiguration.global)
            
            self.primaryIndex = nil
            self.standbyIndex = nil
            self.activeIndex = nil
            self.status = .offline
            self.statusContinuations = .init()
            
            if urls.isEmpty {
                let fulcrum = try await makeFulcrum(nil)
                self.servers = [.init(fulcrum: fulcrum,
                                      endpoint: nil,
                                      retryConfiguration: retryConfiguration.perServer,
                                      gatewayConfiguration: gatewayConfiguration)]
            } else {
                self.servers = try await withThrowingTaskGroup(of: Server.self) { group in
                    for url in urls {
                        group.addTask {
                            let fulcrum = try await makeFulcrum(url)
                            return Server(fulcrum: fulcrum,
                                          endpoint: URL(string: url),
                                          retryConfiguration: retryConfiguration.perServer,
                                          gatewayConfiguration: gatewayConfiguration)
                        }
                    }
                    
                    var builtServers: [Server] = []
                    for try await server in group { builtServers.append(server) }
                    return builtServers
                }
            }
            
            try await bootstrapPersistentHealth()
            try await refreshHealth(now: Date())
            assignRoles()
        }
        
        var currentStatus: Network.Wallet.Status { status }
        func observeStatus() -> AsyncStream<Network.Wallet.Status> {
            AsyncStream { continuation in
                let identifier = UUID()
                continuation.onTermination = { @Sendable _ in
                    Task { await self.removeContinuation(for: identifier) }
                }
                Task { self.addContinuation(identifier: identifier, continuation: continuation) }
            }
        }
        
        private func addContinuation(identifier: UUID,
                                     continuation: AsyncStream<Network.Wallet.Status>.Continuation) {
            continuation.yield(status)
            statusContinuations[identifier] = continuation
        }
        
        private func removeContinuation(for identifier: UUID) {
            statusContinuations.removeValue(forKey: identifier)
        }
        
        func updateStatus(_ newStatus: Network.Wallet.Status) {
            guard newStatus != status else { return }
            status = newStatus
            for continuation in statusContinuations.values {
                continuation.yield(newStatus)
            }
        }
    }
}
