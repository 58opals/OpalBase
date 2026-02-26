// AccountActor+SnapshotModel.swift

import Foundation

extension AccountActor {
    public struct SnapshotModel: Codable {
        public let purpose: DerivationPathModel.PurposeModel
        public let coinType: DerivationPathModel.CoinTypeModel
        public let accountUnhardenedIndex: UInt32
        public let addressBook: AddressModel.BookActor.SnapshotModel
        
        public init(purpose: DerivationPathModel.PurposeModel,
                    coinType: DerivationPathModel.CoinTypeModel,
                    accountUnhardenedIndex: UInt32,
                    addressBook: AddressModel.BookActor.SnapshotModel) {
            self.purpose = purpose
            self.coinType = coinType
            self.accountUnhardenedIndex = accountUnhardenedIndex
            self.addressBook = addressBook
        }
    }
}

extension AccountActor.SnapshotModel: Equatable, Hashable, Sendable {}

extension AccountActor {
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
