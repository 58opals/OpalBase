// Account.swift

import Foundation

public actor Account: Identifiable {
    private let rootExtendedPrivateKey: PrivateKey.Extended
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    let account: DerivationPath.Account
    
    public let id: Data
    public var addressBook: Address.Book
    
    let privacyShaper: PrivacyShaper
    public let privacyConfiguration: PrivacyShaper.Configuration
    
    init(rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account,
         privacyConfiguration: PrivacyShaper.Configuration = .standard) async throws {
        self.rootExtendedPrivateKey = rootExtendedPrivateKey
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        
        self.id = try [self.rootExtendedPrivateKey.serialize(), self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data, self.account.deriveHardenedIndex().data].generateID()
        
        self.addressBook = try await Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                                  purpose: purpose,
                                                  coinType: coinType,
                                                  account: account)
        
        self.privacyConfiguration = privacyConfiguration
        self.privacyShaper = .init(configuration: privacyConfiguration)
    }
    
    init(from snapshot: Account.Snapshot,
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         privacyConfiguration: PrivacyShaper.Configuration = .standard) async throws {
        try await self.init(rootExtendedPrivateKey: rootExtendedPrivateKey,
                            purpose: purpose,
                            coinType: coinType,
                            account: try .init(rawIndexInteger: snapshot.account),
                            privacyConfiguration: privacyConfiguration)
        try await self.addressBook.applySnapshot(snapshot.addressBook)
    }
}

extension Account: Equatable {
    public static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.id == rhs.id
    }
}

extension Account {
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

extension Account {
    public var derivationPath: (purpose: DerivationPath.Purpose,
                                coinType: DerivationPath.CoinType,
                                account: DerivationPath.Account) {
        return (self.purpose, self.coinType, self.account)
    }
}

extension Account {
    public func loadBalanceFromCache() async throws -> Satoshi {
        try await addressBook.calculateCachedTotalBalance()
    }
}

extension Account {
    public func loadTransactionHistory() async -> [Transaction.History.Record] {
        await addressBook.transactionLog.listRecords()
    }
}
