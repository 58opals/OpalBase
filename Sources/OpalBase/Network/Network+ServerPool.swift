// Network+ServerPool.swift

import Foundation

extension Network {
    public actor ServerPool {
        public struct Node: Identifiable, Sendable {
            public var id: URL { url }
            public let url: URL
            public var latency: TimeInterval?
            public var failureCount: Int = 0
            public var quarantineUntil: Date?
            
            public var isQuarantined: Bool {
                if let until = quarantineUntil {
                    return until > Date()
                }
                return false
            }
        }
        
        public enum Status: Sendable {
            case idle
            case probing
            case healthy
            case degraded
            case unhealthy
        }
        
        public typealias Prober = @Sendable (URL) async throws -> TimeInterval
        
        nonisolated let prober: Prober
        private var nodes: [Node]
        private var status: Status = .idle
        private var continuations: [UUID: AsyncStream<Status>.Continuation] = [:]
        
        public init(urls: [URL], prober: @escaping Prober) {
            self.nodes = urls.map { Node(url: $0) }
            self.prober = prober
        }
        
        static func defaultProber(_ url: URL) async throws -> TimeInterval {
            let clock = ContinuousClock()
            let start = clock.now
            var request = URLRequest(url: url)
            request.httpMethod = "HEAD"
            _ = try await URLSession.shared.data(for: request)
            let end = clock.now
            
            let durationComponents = start.duration(to: end).components
            let timeInterval = Double(durationComponents.seconds) + (Double(durationComponents.attoseconds) / 1_000_000_000_000_000_000)
            
            return timeInterval
        }
        
        public func snapshot() -> [Node] { nodes }
        
        public var currentStatus: Status { status }
        
        public var primary: URL? { nodes.first(where: { !$0.isQuarantined })?.url }
        
        public var standbys: [URL] {
            nodes.dropFirst().filter { !$0.isQuarantined }.map(\.url)
        }
        
        public func observeStatus() -> AsyncStream<Status> {
            AsyncStream { continuation in
                Task { self.addContinuation(continuation) }
            }
        }
        
        private func addContinuation(_ continuation: AsyncStream<Status>.Continuation) {
            let identifier = UUID()
            continuation.onTermination = { @Sendable _ in
                Task { await self.removeContinuation(identifier) }
            }
            continuations[identifier] = continuation
            continuation.yield(status)
        }
        
        private func removeContinuation(_ identifier: UUID) {
            continuations.removeValue(forKey: identifier)
        }
        
        private func updateStatus(_ newStatus: Status) {
            guard newStatus != status else { return }
            status = newStatus
            for continuation in continuations.values { continuation.yield(newStatus) }
        }
        
        public func process(url: URL, latency: TimeInterval) {
            guard let index = nodes.firstIndex(where: { $0.url == url }) else { return }
            nodes[index].latency = latency
            nodes[index].failureCount = 0
            nodes[index].quarantineUntil = nil
        }
        
        public func processFailure(url: URL, error: Swift.Error) {
            guard let index = nodes.firstIndex(where: { $0.url == url }) else { return }
            nodes[index].failureCount += 1
            let backoff = min(pow(2.0, Double(nodes[index].failureCount)), 60)
            nodes[index].quarantineUntil = Date().addingTimeInterval(backoff)
        }
        
        public func finalizeProbing() {
            let healthy = nodes.filter { !$0.isQuarantined && $0.latency != nil }
            let healthyCount = healthy.count
            if healthyCount == 0 {
                updateStatus(.unhealthy)
            } else if healthyCount < nodes.count {
                updateStatus(.degraded)
            } else {
                updateStatus(.healthy)
            }
            
            nodes.sort { lhs, rhs in
                switch (lhs.isQuarantined, rhs.isQuarantined) {
                case (true, false): return false
                case (false, true): return true
                default:
                    return (lhs.latency ?? .greatestFiniteMagnitude) < (rhs.latency ?? .greatestFiniteMagnitude)
                }
            }
        }
    }
}
