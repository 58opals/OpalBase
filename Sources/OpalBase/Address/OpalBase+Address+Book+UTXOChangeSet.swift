// OpalBase+Address+Book+UTXOChangeSet.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct UTXOChangeSet {
        public let address: OpalBase.Address
        public let previous: [OpalBase.Transaction.Output.Unspent]
        public let updated: [OpalBase.Transaction.Output.Unspent]
        public let inserted: [OpalBase.Transaction.Output.Unspent]
        public let removed: [OpalBase.Transaction.Output.Unspent]
        public let retained: [OpalBase.Transaction.Output.Unspent]
        public let balance: OpalBase.Satoshi
        public let timestamp: Date
        
        public init(address: OpalBase.Address,
                    previous: [OpalBase.Transaction.Output.Unspent],
                    updated: [OpalBase.Transaction.Output.Unspent],
                    timestamp: Date = .now) throws {
            self.address = address
            self.previous = previous
            self.updated = updated
            
            let previousSet = Set(previous)
            let updatedSet = Set(updated)
            let insertedSet = updatedSet.subtracting(previousSet)
            self.inserted = insertedSet.sorted { $0.compareOrder(before: $1) }
            let removedSet = previousSet.subtracting(updatedSet)
            self.removed = removedSet.sorted { $0.compareOrder(before: $1) }
            let retainedSet = previousSet.intersection(updatedSet)
            self.retained = retainedSet.sorted { $0.compareOrder(before: $1) }
            self.balance = try Self.makeBalance(from: updatedSet)
            self.timestamp = timestamp
        }
    }
}

extension _OpalBase.Address.Book.UTXOChangeSet: Sendable {}
extension _OpalBase.Address.Book.UTXOChangeSet: Equatable {}

private extension _OpalBase.Address.Book.UTXOChangeSet {
    static func makeBalance(from utxos: Set<OpalBase.Transaction.Output.Unspent>) throws -> OpalBase.Satoshi {
        return try utxos.sumSatoshi { try OpalBase.Satoshi($0.value) }
    }
}
