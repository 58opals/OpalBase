// Account+Snapshot.swift

import Foundation

extension Account {
    public struct Snapshot: Codable {
        public let purpose: DerivationPath.Purpose
        public let coinType: DerivationPath.CoinType
        public let account: UInt32
        public let addressBook: Address.Book.Snapshot
        
        public init(purpose: DerivationPath.Purpose,
                    coinType: DerivationPath.CoinType,
                    account: UInt32,
                    addressBook: Address.Book.Snapshot) {
            self.purpose = purpose
            self.coinType = coinType
            self.account = account
            self.addressBook = addressBook
        }
    }
}

extension Account.Snapshot: Sendable {}

extension Account {
    public func makeSnapshot() async -> Snapshot {
        let bookSnap = await addressBook.makeSnapshot()
        return Snapshot(purpose: purpose,
                        coinType: coinType,
                        account: self.account.unhardenedIndex,
                        addressBook: bookSnap)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) async throws {
        try await addressBook.applySnapshot(snapshot.addressBook)
    }
}
