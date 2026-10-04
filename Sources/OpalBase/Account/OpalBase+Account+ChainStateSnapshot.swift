// OpalBase+Account+ChainStateSnapshot.swift

import Foundation

extension _OpalBase.Account {
    /// One coherent read of public chain state for a consumer's durable projection.
    public struct ChainStateSnapshot: Sendable {
        public let addressBook: Snapshot.AddressBook
        public let history: [OpalBase.Transaction.History.Record]
        public let balance: OpalBase.Satoshi
    }

    public func makeChainStateSnapshot() async throws -> ChainStateSnapshot {
        let state = try await addressBook.makeChainStateSnapshot()
        return ChainStateSnapshot(addressBook: .init(state.addressBook), history: state.history, balance: state.balance)
    }
}

extension _OpalBase.Address.Book {
    func makeChainStateSnapshot() throws -> (addressBook: Snapshot, history: [OpalBase.Transaction.History.Record], balance: OpalBase.Satoshi) {
        try (makeSnapshot(), transactionLog.listRecords(), calculateCachedTotalBalance())
    }
}
