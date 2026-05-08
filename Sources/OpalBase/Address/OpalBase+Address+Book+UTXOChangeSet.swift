// OpalBase+Address+Book+UTXOChangeSet.swift

import Foundation

extension _OpalBase.Address.Book {
    struct UTXOChangeSet {
        let address: OpalBase.Address
        let previous: [OpalBase.Transaction.Output.Unspent]
        let updated: [OpalBase.Transaction.Output.Unspent]
        let inserted: [OpalBase.Transaction.Output.Unspent]
        let removed: [OpalBase.Transaction.Output.Unspent]
        let retained: [OpalBase.Transaction.Output.Unspent]
        let balance: OpalBase.Satoshi
        let timestamp: Date
        
        init(address: OpalBase.Address,
                    previous: [OpalBase.Transaction.Output.Unspent],
                    updated: [OpalBase.Transaction.Output.Unspent],
                    timestamp: Date = .now) throws {
            self.address = address
            self.previous = previous
            self.updated = updated
            
            let previousByOutpoint = Self.makeOutpointIndex(previous)
            let updatedByOutpoint = Self.makeOutpointIndex(updated)
            self.inserted = updated.filter { updatedOutput in
                guard let previousOutput = previousByOutpoint[UTXORepository.Outpoint(updatedOutput)] else {
                    return true
                }
                return !Self.hasMatchingPayload(previousOutput, updatedOutput)
            }.sorted { $0.compareOrder(before: $1) }
            self.removed = previous.filter { previousOutput in
                guard let updatedOutput = updatedByOutpoint[UTXORepository.Outpoint(previousOutput)] else {
                    return true
                }
                return !Self.hasMatchingPayload(previousOutput, updatedOutput)
            }.sorted { $0.compareOrder(before: $1) }
            self.retained = previous.filter { previousOutput in
                guard let updatedOutput = updatedByOutpoint[UTXORepository.Outpoint(previousOutput)] else {
                    return false
                }
                return Self.hasMatchingPayload(previousOutput, updatedOutput)
            }.sorted { $0.compareOrder(before: $1) }
            self.balance = try Self.makeBalance(from: Set(updated))
            self.timestamp = timestamp
        }
    }
}

extension _OpalBase.Address.Book.UTXOChangeSet: Sendable {}
extension _OpalBase.Address.Book.UTXOChangeSet: Equatable {}

private extension _OpalBase.Address.Book.UTXOChangeSet {
    static func makeOutpointIndex(
        _ utxos: [OpalBase.Transaction.Output.Unspent]
    ) -> [OpalBase.Address.Book.UTXORepository.Outpoint: OpalBase.Transaction.Output.Unspent] {
        utxos.reduce(into: .init()) { result, utxo in
            result[OpalBase.Address.Book.UTXORepository.Outpoint(utxo)] = utxo
        }
    }
    
    static func hasMatchingPayload(
        _ left: OpalBase.Transaction.Output.Unspent,
        _ right: OpalBase.Transaction.Output.Unspent
    ) -> Bool {
        left.value == right.value
        && left.lockingScript == right.lockingScript
        && left.tokenData == right.tokenData
    }
    
    static func makeBalance(from utxos: Set<OpalBase.Transaction.Output.Unspent>) throws -> OpalBase.Satoshi {
        return try utxos.sumSatoshi { try OpalBase.Satoshi($0.value) }
    }
}
