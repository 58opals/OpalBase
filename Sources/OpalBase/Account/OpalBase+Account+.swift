// OpalBase+Account+.swift

import Foundation

extension OpalBase {
    public actor Account: Identifiable {
        private let rootExtendedPrivateKey: OpalBase.PrivateKey.ExtendedModel

        let purpose: OpalBase.DerivationPath.PurposeModel
        let coinType: OpalBase.DerivationPath.CoinTypeModel
        let account: OpalBase.DerivationPath.Account

        public let id: Data
        public let addressBook: OpalBase.Address.Book

        let privacyShaper: PrivacyShaperActor
        public let privacyConfiguration: PrivacyShaperActor.Configuration

        init(
            rootExtendedPrivateKey: OpalBase.PrivateKey.ExtendedModel,
            purpose: OpalBase.DerivationPath.PurposeModel,
            coinType: OpalBase.DerivationPath.CoinTypeModel,
            account: OpalBase.DerivationPath.Account,
            addressBook: OpalBase.Address.Book,
            privacyConfiguration: PrivacyShaperActor.Configuration = .standard
        ) throws {
            self.rootExtendedPrivateKey = rootExtendedPrivateKey
            self.purpose = purpose
            self.coinType = coinType
            self.account = account

            self.id = try [
                self.rootExtendedPrivateKey.serialize(),
                self.purpose.hardenedIndex.data,
                self.coinType.hardenedIndex.data,
                self.account.deriveHardenedIndex().data,
            ].generateID()
            self.addressBook = addressBook
            self.privacyConfiguration = privacyConfiguration
            self.privacyShaper = .init(configuration: privacyConfiguration)
        }

        init(
            rootExtendedPrivateKey: OpalBase.PrivateKey.ExtendedModel,
            purpose: OpalBase.DerivationPath.PurposeModel,
            coinType: OpalBase.DerivationPath.CoinTypeModel,
            account: OpalBase.DerivationPath.Account,
            privacyConfiguration: PrivacyShaperActor.Configuration = .standard
        ) async throws {
            let addressBook = try await OpalBase.Address.Book(
                rootExtendedPrivateKey: rootExtendedPrivateKey,
                purpose: purpose,
                coinType: coinType,
                account: account
            )

            try self.init(
                rootExtendedPrivateKey: rootExtendedPrivateKey,
                purpose: purpose,
                coinType: coinType,
                account: account,
                addressBook: addressBook,
                privacyConfiguration: privacyConfiguration
            )
        }

        init(
            from snapshot: OpalBase.Account.SnapshotModel,
            rootExtendedPrivateKey: OpalBase.PrivateKey.ExtendedModel,
            purpose: OpalBase.DerivationPath.PurposeModel,
            coinType: OpalBase.DerivationPath.CoinTypeModel,
            privacyConfiguration: PrivacyShaperActor.Configuration = .standard
        ) async throws {
            let accountPath = try OpalBase.DerivationPath.Account(rawIndexInteger: snapshot.accountUnhardenedIndex)
            let addressBook = try await OpalBase.Address.Book(
                from: snapshot.addressBook,
                rootExtendedPrivateKey: rootExtendedPrivateKey,
                purpose: purpose,
                coinType: coinType,
                account: accountPath
            )

            try self.init(
                rootExtendedPrivateKey: rootExtendedPrivateKey,
                purpose: purpose,
                coinType: coinType,
                account: accountPath,
                addressBook: addressBook,
                privacyConfiguration: privacyConfiguration
            )
        }
    }
}

extension _OpalBase.Account: Equatable {
    public static func == (lhs: OpalBase.Account, rhs: OpalBase.Account) -> Bool {
        lhs.id == rhs.id
    }
}

extension _OpalBase.Account {
    public var rawIndex: UInt32 {
        account.unhardenedIndex
    }
    
    public var unhardenedIndex: UInt32 {
        account.unhardenedIndex
    }
    
    public func deriveHardenedIndex() throws -> UInt32 {
        try account.deriveHardenedIndex()
    }
}

extension _OpalBase.Account {
    public var derivationPath: (purpose: OpalBase.DerivationPath.PurposeModel,
                                coinType: OpalBase.DerivationPath.CoinTypeModel,
                                account: OpalBase.DerivationPath.Account) {
        (purpose, coinType, account)
    }
}

extension _OpalBase.Account {
    public func loadBalanceFromCache() async throws -> OpalBase.Satoshi {
        try await addressBook.calculateCachedTotalBalance()
    }
}

extension _OpalBase.Account {
    public func loadTransactionHistory() async -> [OpalBase.Transaction.HistoryModel.Record] {
        await listTransactions()
    }
}

// MARK: - OpalBase.Address BookActor Accessors
extension _OpalBase.Account {
    public func listEntries(for usage: OpalBase.DerivationPath.UsageModel) async -> [OpalBase.Address.Book.EntryModel] {
        await addressBook.listEntries(for: usage)
    }
    
    public func selectNextEntry(for usage: OpalBase.DerivationPath.UsageModel) async throws -> OpalBase.Address.Book.EntryModel {
        try await addressBook.selectNextEntry(for: usage)
    }
    
    public func readGapLimit() async -> Int {
        await addressBook.readGapLimit()
    }
}
