// OpalBase+Network+ChainRefreshGeneration.swift

import Foundation
import Synchronization

extension _OpalBase.Network {
    /// Serializes generation invalidation with short, non-suspending chain-state commits.
    final class ChainRefreshGeneration: Sendable {
        private let current = Mutex<UInt64?>(0)

        func makePermit() -> ChainRefreshMutationPermit {
            current.withLock { ChainRefreshMutationPermit(owner: self, generation: $0) }
        }

        func invalidate() {
            current.withLock { generation in
                if let value = generation { generation = value &+ 1 }
            }
        }

        func finish() { current.withLock { $0 = nil } }

        func isCurrent(_ generation: UInt64?) -> Bool {
            current.withLock { $0 != nil && $0 == generation }
        }

        func commit<Value>(generation: UInt64?, mutation: () throws -> Value) throws -> Value {
            try current.withLock { current in
                try Task.checkCancellation()
                guard current != nil, current == generation else { throw CancellationError() }
                return try mutation()
            }
        }
    }

    struct ChainRefreshMutationPermit: Sendable {
        let owner: ChainRefreshGeneration
        let generation: UInt64?
        var isCurrent: Bool { owner.isCurrent(generation) }

        func commit<Value>(_ mutation: () throws -> Value) throws -> Value {
            try owner.commit(generation: generation, mutation: mutation)
        }
    }
}

extension _OpalBase.Address.Book {
    func commitChainRefresh<Value>(using permit: OpalBase.Network.ChainRefreshMutationPermit?, mutation: () throws -> Value) throws -> Value {
        if let permit { return try permit.commit(mutation) }
        try Task.checkCancellation()
        return try mutation()
    }
}
