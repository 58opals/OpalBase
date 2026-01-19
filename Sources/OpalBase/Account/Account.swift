// Account.swift

import Foundation

public actor Account: Identifiable {
    private let rootExtendedPrivateKey: PrivateKey.Extended
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    let account: DerivationPath.Account
    
    public let id: Data
    public let addressBook: Address.Book
    
    let privacyShaper: PrivacyShaper
    public let privacyConfiguration: PrivacyShaper.Configuration
    
    init(rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account,
         addressBook: Address.Book,
         privacyConfiguration: PrivacyShaper.Configuration = .standard) throws {
        self.rootExtendedPrivateKey = rootExtendedPrivateKey
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        
        self.id = try [self.rootExtendedPrivateKey.serialize(), self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data, self.account.deriveHardenedIndex().data].generateID()
        self.addressBook = addressBook
        self.privacyConfiguration = privacyConfiguration
        self.privacyShaper = .init(configuration: privacyConfiguration)
    }
    
    init(rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account,
         privacyConfiguration: PrivacyShaper.Configuration = .standard) async throws {
        let addressBook = try await Address.Book(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                                 purpose: purpose,
                                                 coinType: coinType,
                                                 account: account)
        
        try self.init(rootExtendedPrivateKey: rootExtendedPrivateKey,
                      purpose: purpose,
                      coinType: coinType,
                      account: account,
                      addressBook: addressBook,
                      privacyConfiguration: privacyConfiguration)
    }
    
    init(from snapshot: Account.Snapshot,
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         privacyConfiguration: PrivacyShaper.Configuration = .standard) async throws {
        let accountPath = try DerivationPath.Account(rawIndexInteger: snapshot.accountUnhardenedIndex)
        let addressBook = try await Address.Book(from: snapshot.addressBook,
                                                 rootExtendedPrivateKey: rootExtendedPrivateKey,
                                                 purpose: purpose,
                                                 coinType: coinType,
                                                 account: accountPath)
        
        try self.init(rootExtendedPrivateKey: rootExtendedPrivateKey,
                      purpose: purpose,
                      coinType: coinType,
                      account: accountPath,
                      addressBook: addressBook,
                      privacyConfiguration: privacyConfiguration)
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
        await listTransactions()
    }
}

// MARK: - Address Book Accessors
extension Account {
    public func listEntries(for usage: DerivationPath.Usage) async -> [Address.Book.Entry] {
        await addressBook.listEntries(for: usage)
    }
    
    public func selectNextEntry(for usage: DerivationPath.Usage) async throws -> Address.Book.Entry {
        try await addressBook.selectNextEntry(for: usage)
    }
    
    public func readGapLimit() async -> Int {
        await addressBook.readGapLimit()
    }
}
