// OpalBase+Account+.swift

import Foundation
import OpalCrypto

extension OpalBase {
    public actor Account: Identifiable {
        private let rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate

        let purpose: OpalBase.Key.DerivationPath.Purpose
        let coinType: OpalBase.Key.DerivationPath.CoinType
        let account: OpalBase.Key.DerivationPath.Account

        public let id: Data
        let addressBook: OpalBase.Address.Book

        let privacyShaper: PrivacyShaperActor
        let privacyConfiguration: PrivacyShaperActor.Configuration

        init(
            rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate,
            purpose: OpalBase.Key.DerivationPath.Purpose,
            coinType: OpalBase.Key.DerivationPath.CoinType,
            account: OpalBase.Key.DerivationPath.Account,
            addressBook: OpalBase.Address.Book,
            privacyConfiguration: PrivacyShaperActor.Configuration = .standard
        ) throws {
            self.rootExtendedPrivateKey = rootExtendedPrivateKey
            self.purpose = purpose
            self.coinType = coinType
            self.account = account

            self.id = try [
                OpalCryptoAdapter.serializedExtendedKeyData(self.rootExtendedPrivateKey.serialize()),
                self.purpose.hardenedIndex.data,
                self.coinType.hardenedIndex.data,
                self.account.deriveHardenedIndex().data,
            ].generateID()
            self.addressBook = addressBook
            self.privacyConfiguration = privacyConfiguration
            self.privacyShaper = .init(configuration: privacyConfiguration)
        }

        init(
            rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate,
            purpose: OpalBase.Key.DerivationPath.Purpose,
            coinType: OpalBase.Key.DerivationPath.CoinType,
            account: OpalBase.Key.DerivationPath.Account,
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
            from snapshot: OpalBase.Account.Snapshot,
            rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate,
            purpose: OpalBase.Key.DerivationPath.Purpose,
            coinType: OpalBase.Key.DerivationPath.CoinType,
            privacyConfiguration: PrivacyShaperActor.Configuration = .standard
        ) async throws {
            let accountPath = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: snapshot.accountUnhardenedIndex)
            let addressBook = try await OpalBase.Address.Book(
                from: snapshot.addressBook.addressBookSnapshot,
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
    public var derivationPath: (purpose: OpalBase.Key.DerivationPath.Purpose,
                                coinType: OpalBase.Key.DerivationPath.CoinType,
                                account: OpalBase.Key.DerivationPath.Account) {
        (purpose, coinType, account)
    }
}

extension _OpalBase.Account {
    public func loadBalanceFromCache() async throws -> OpalBase.Satoshi {
        try await addressBook.calculateCachedTotalBalance()
    }
}

extension _OpalBase.Account {
    public func loadTransactionHistory() async -> [OpalBase.Transaction.History.Record] {
        await listTransactions()
    }
}

// MARK: - OpalBase.Address.Book Accessors
extension _OpalBase.Account {
    /// Lists wallet-derived addresses for a derivation usage.
    public func listDerivedAddresses(for usage: OpalBase.Key.DerivationPath.Usage) async -> [DerivedAddress] {
        await listEntries(for: usage).map(DerivedAddress.init)
    }

    func listEntries(for usage: OpalBase.Key.DerivationPath.Usage) async -> [OpalBase.Address.Book.Entry] {
        await addressBook.listEntries(for: usage)
    }
    
    /// Selects the next derived address for the requested usage without exposing
    /// the underlying address-book entry.
    public func selectNextDerivedAddress(for usage: OpalBase.Key.DerivationPath.Usage) async throws -> DerivedAddress {
        try await DerivedAddress(selectNextEntry(for: usage))
    }

    func selectNextEntry(for usage: OpalBase.Key.DerivationPath.Usage) async throws -> OpalBase.Address.Book.Entry {
        try await addressBook.selectNextEntry(for: usage)
    }
    
    func readGapLimit() async -> Int {
        await addressBook.readGapLimit()
    }
}
