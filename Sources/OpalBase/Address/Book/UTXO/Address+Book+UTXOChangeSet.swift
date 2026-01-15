// Address+Book+UTXOChangeSet.swift

import Foundation

extension Address.Book {
    public struct UTXOChangeSet {
        public let address: Address
        public let previous: [Transaction.Output.Unspent]
        public let updated: [Transaction.Output.Unspent]
        public let inserted: [Transaction.Output.Unspent]
        public let removed: [Transaction.Output.Unspent]
        public let retained: [Transaction.Output.Unspent]
        public let balance: Satoshi
        public let timestamp: Date
        
        public init(address: Address,
                    previous: [Transaction.Output.Unspent],
                    updated: [Transaction.Output.Unspent],
                    timestamp: Date = .now) throws {
            self.address = address
            self.previous = previous
            self.updated = updated
            
            let previousSet = Set(previous)
            let updatedSet = Set(updated)
            let insertedSet = updatedSet.subtracting(previousSet)
            self.inserted = insertedSet.sorted { $0.isOrdered(before: $1) }
            let removedSet = previousSet.subtracting(updatedSet)
            self.removed = removedSet.sorted { $0.isOrdered(before: $1) }
            let retainedSet = previousSet.intersection(updatedSet)
            self.retained = retainedSet.sorted { $0.isOrdered(before: $1) }
            self.balance = try Self.makeBalance(from: updatedSet)
            self.timestamp = timestamp
        }
    }
}

extension Address.Book.UTXOChangeSet: Sendable {}
extension Address.Book.UTXOChangeSet: Equatable {}

private extension Address.Book.UTXOChangeSet {
    static func makeBalance(from utxos: Set<Transaction.Output.Unspent>) throws -> Satoshi {
        var total: Satoshi = .init()
        for utxo in utxos {
            total = try total + Satoshi(utxo.value)
        }
        
        return total
    }
}
