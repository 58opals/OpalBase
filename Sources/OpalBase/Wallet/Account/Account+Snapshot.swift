// Account+Snapshot.swift

import Foundation

extension Account {
    public struct Snapshot: Codable {
        public let purpose: DerivationPath.Purpose
        public let coinType: DerivationPath.CoinType
        public let accountUnhardenedIndex: UInt32
        public let addressBook: Address.Book.Snapshot
        
        public init(purpose: DerivationPath.Purpose,
                    coinType: DerivationPath.CoinType,
                    accountUnhardenedIndex: UInt32,
                    addressBook: Address.Book.Snapshot) {
            self.purpose = purpose
            self.coinType = coinType
            self.accountUnhardenedIndex = accountUnhardenedIndex
            self.addressBook = addressBook
        }
    }
}

extension Account.Snapshot: Sendable {}

extension Account.Snapshot: Equatable {}

extension Account {
    public func makeSnapshot() async -> Snapshot {
        let bookSnap = await addressBook.makeSnapshot()
        return Snapshot(purpose: purpose,
                        coinType: coinType,
                        accountUnhardenedIndex: self.account.unhardenedIndex,
                        addressBook: bookSnap)
    }
    
    public func refresh(with snapshot: Snapshot) async throws {
        guard snapshot.purpose == purpose,
              snapshot.coinType == coinType,
              snapshot.accountUnhardenedIndex == self.account.unhardenedIndex else {
            throw Error.snapshotDoesNotMatchAccount
        }
        try await addressBook.refresh(with: snapshot.addressBook)
    }
}
