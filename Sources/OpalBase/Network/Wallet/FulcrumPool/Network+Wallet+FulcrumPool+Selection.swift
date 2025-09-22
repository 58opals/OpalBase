// Network+Wallet+FulcrumPool+Selection.swift

import Foundation

extension Network.Wallet.FulcrumPool {
    struct RoleMetrics: Sendable {
        let index: Int
        let nextRetry: Date
        let lastLatency: TimeInterval?
        
        init(index: Int, nextRetry: Date, lastLatency: TimeInterval?) {
            self.index = index
            self.nextRetry = nextRetry
            self.lastLatency = lastLatency
        }
    }
    
    static func determineRoles(
        for metrics: [RoleMetrics],
        now: Date,
        preferredPrimary: Int?
    ) -> (primary: Int?, standby: Int?) {
        var available = metrics.filter { now >= $0.nextRetry }
        available.sort { lhs, rhs in
            let lhsLatency = lhs.lastLatency ?? .greatestFiniteMagnitude
            let rhsLatency = rhs.lastLatency ?? .greatestFiniteMagnitude
            if lhsLatency == rhsLatency { return lhs.index < rhs.index }
            return lhsLatency < rhsLatency
        }
        
        if let preferredPrimary,
           let preferredIndex = available.firstIndex(where: { $0.index == preferredPrimary })
        {
            let preferred = available.remove(at: preferredIndex)
            available.insert(preferred, at: 0)
        }
        
        var primary = available.first?.index
        var standby = available.dropFirst().first?.index
        
        let deferred = metrics
            .filter { now < $0.nextRetry }
            .sorted { lhs, rhs in
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
}

extension Network.Wallet.FulcrumPool.PoolState {
    func assignRoles(now: Date = .init(), preferredPrimary: Int? = nil) {
        guard !servers.isEmpty else {
            primaryIndex = nil
            standbyIndex = nil
            activeIndex = nil
            return
        }
        
        let metrics = servers.enumerated().map { index, server in
            Network.Wallet.FulcrumPool.RoleMetrics(index: index,
                                                   nextRetry: server.nextRetry,
                                                   lastLatency: server.lastLatency)
        }
        let roles = Network.Wallet.FulcrumPool.determineRoles(for: metrics,
                                                              now: now,
                                                              preferredPrimary: preferredPrimary)
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
    
    func prioritizedServerIndices(now: Date = .init()) -> [Int] {
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
