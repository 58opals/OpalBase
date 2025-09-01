// NetworkCoordinator.swift

import Foundation

extension Network {
    public actor Coordinator {
        public enum State: Sendable {
            case idle
            case connecting
            case live
            case degraded
            case failover
        }
        
        private let pool: ServerPool
        private var state: State = .idle
        private var continuations: [UUID: AsyncStream<State>.Continuation] = [:]
        
        public init(pool: ServerPool) {
            self.pool = pool
        }
        
        public var currentState: State { state }
        
        private func updateState(_ newState: State) {
            guard newState != state else { return }
            state = newState
            for continuation in continuations.values { continuation.yield(newState) }
        }
        
        private func addContinuation(_ continuation: AsyncStream<State>.Continuation) {
            let identifier = UUID()
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(identifier) }
            }
            continuations[identifier] = continuation
            continuation.yield(state)
        }
        
        private func removeContinuation(_ identifier: UUID) {
            continuations.removeValue(forKey: identifier)
        }
        
        public func observeState() -> AsyncStream<State> {
            AsyncStream { continuation in
                Task { self.addContinuation(continuation) }
            }
        }
        
        public func connect() async {
            guard state == .idle else { return }
            updateState(.connecting)
            
            let nodes = await pool.snapshot()
            let prober = pool.prober
            await withTaskGroup(of: Void.self) { group in
                for node in nodes {
                    group.addTask {
                        do {
                            let latency = try await prober(node.url)
                            await self.pool.process(url: node.url, latency: latency)
                        } catch {
                            await self.pool.processFailure(url: node.url, error: error)
                        }
                    }
                }
                await group.waitForAll()
            }
            
            await pool.finalizeProbing()
            switch await pool.currentStatus {
            case .healthy:
                updateState(.live)
            case .degraded:
                updateState(.degraded)
            case .unhealthy:
                updateState(.failover)
            case .idle, .probing:
                updateState(.connecting)
            }
        }
    }
}
