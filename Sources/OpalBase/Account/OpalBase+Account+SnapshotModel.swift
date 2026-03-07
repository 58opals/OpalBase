// OpalBase+Account+SnapshotModel.swift

import Foundation

extension _OpalBase.Account {
    public struct SnapshotModel: Codable {
        public let purpose: OpalBase.DerivationPath.PurposeModel
        public let coinType: OpalBase.DerivationPath.CoinTypeModel
        public let accountUnhardenedIndex: UInt32
        public let addressBook: OpalBase.Address.Book.SnapshotModel
        
        public init(purpose: OpalBase.DerivationPath.PurposeModel,
                    coinType: OpalBase.DerivationPath.CoinTypeModel,
                    accountUnhardenedIndex: UInt32,
                    addressBook: OpalBase.Address.Book.SnapshotModel) {
            self.purpose = purpose
            self.coinType = coinType
            self.accountUnhardenedIndex = accountUnhardenedIndex
            self.addressBook = addressBook
        }
    }
}

extension _OpalBase.Account.SnapshotModel: Equatable, Hashable, Sendable {}

extension _OpalBase.Account {
    public func makeSnapshot() async -> SnapshotModel {
        let bookSnap = await addressBook.makeSnapshot()
        return SnapshotModel(purpose: purpose,
                        coinType: coinType,
                        accountUnhardenedIndex: self.account.unhardenedIndex,
                        addressBook: bookSnap)
    }
    
    public func refresh(with snapshot: SnapshotModel) async throws {
        guard snapshot.purpose == purpose,
              snapshot.coinType == coinType,
              snapshot.accountUnhardenedIndex == self.account.unhardenedIndex else {
            throw Error.snapshotDoesNotMatchAccount
        }
        try await addressBook.refresh(with: snapshot.addressBook)
    }
}
