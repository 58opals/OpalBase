// AddressModel+BookActor+UTXOChangeSetModel.swift

import Foundation

extension AddressModel.BookActor {
    public struct UTXOChangeSetModel {
        public let address: AddressModel
        public let previous: [TransactionModel.OutputModel.UnspentModel]
        public let updated: [TransactionModel.OutputModel.UnspentModel]
        public let inserted: [TransactionModel.OutputModel.UnspentModel]
        public let removed: [TransactionModel.OutputModel.UnspentModel]
        public let retained: [TransactionModel.OutputModel.UnspentModel]
        public let balance: SatoshiModel
        public let timestamp: Date
        
        public init(address: AddressModel,
                    previous: [TransactionModel.OutputModel.UnspentModel],
                    updated: [TransactionModel.OutputModel.UnspentModel],
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

extension AddressModel.BookActor.UTXOChangeSetModel: Sendable {}
extension AddressModel.BookActor.UTXOChangeSetModel: Equatable {}

private extension AddressModel.BookActor.UTXOChangeSetModel {
    static func makeBalance(from utxos: Set<TransactionModel.OutputModel.UnspentModel>) throws -> SatoshiModel {
        return try utxos.sumSatoshi { try SatoshiModel($0.value) }
    }
}
