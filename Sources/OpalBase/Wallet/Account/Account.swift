// Account.swift

import Foundation

public actor Account: Identifiable {
    private let rootExtendedPrivateKey: PrivateKey.Extended
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    let account: DerivationPath.Account
    
    let storageSettings: Storage.Settings
    
    public let id: Data
    public var addressBook: Address.Book
    
    let privacyShaper: PrivacyShaper
    public let privacyConfiguration: PrivacyShaper.Configuration
    
    init(fulcrumServerURLs: [String] = .init(),
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         account: DerivationPath.Account,
         privacyConfiguration: PrivacyShaper.Configuration = .standard,
         storageSettings: Storage.Settings = .init()) async throws {
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
        self.storageSettings = storageSettings
    }
    
    init(from snapshot: Account.Snapshot,
         fulcrumServerURLs: [String] = .init(),
         rootExtendedPrivateKey: PrivateKey.Extended,
         purpose: DerivationPath.Purpose,
         coinType: DerivationPath.CoinType,
         privacyConfiguration: PrivacyShaper.Configuration = .standard,
         storageSettings: Storage.Settings = .init()) async throws {
        try await self.init(fulcrumServerURLs: fulcrumServerURLs,
                            rootExtendedPrivateKey: rootExtendedPrivateKey,
                            purpose: purpose,
                            coinType: coinType,
                            account: try .init(rawIndexInteger: snapshot.account),
                            privacyConfiguration: privacyConfiguration,
                            storageSettings: storageSettings)
        try await self.addressBook.applySnapshot(snapshot.addressBook)
    }
}

extension Account: Equatable {
    public static func == (lhs: Account, rhs: Account) -> Bool {
        lhs.id == rhs.id
    }
}

extension Account {
    public enum Error: Swift.Error {
        case balanceFetchTimeout(Address)
        case paymentHasNoRecipients
        case paymentExceedsMaximumAmount
        case coinSelectionFailed(Swift.Error)
        case transactionBuildFailed(Swift.Error)
        case outboxPersistenceFailed(Swift.Error)
        case broadcastFailed(Swift.Error)
        case feePreferenceUnavailable(Swift.Error)
    }
}

extension Account.Error: Equatable {
    public static func == (lhs: Account.Error, rhs: Account.Error) -> Bool {
        switch (lhs, rhs) {
        case (.paymentHasNoRecipients, .paymentHasNoRecipients),
            (.paymentExceedsMaximumAmount, .paymentExceedsMaximumAmount):
            return true
        case (.balanceFetchTimeout(let leftAddress), .balanceFetchTimeout(let rightAddress)):
            return leftAddress == rightAddress
        case (.coinSelectionFailed(let leftError), .coinSelectionFailed(let rightError)),
            (.transactionBuildFailed(let leftError), .transactionBuildFailed(let rightError)),
            (.outboxPersistenceFailed(let leftError), .outboxPersistenceFailed(let rightError)),
            (.broadcastFailed(let leftError), .broadcastFailed(let rightError)),
            (.feePreferenceUnavailable(let leftError), .feePreferenceUnavailable(let rightError)):
            return leftError.localizedDescription == rightError.localizedDescription
        default:
            return false
        }
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
    public func loadTransactionHistory() async -> [Address.Book.History.Transaction.Record] {
        await addressBook.listTransactionHistory()
    }
    
    public func loadLedgerEntries(using storage: Storage) async -> [Storage.AccountSnapshot.TransactionLedger.Entry] {
        let accountIndex = account.unhardenedIndex
        guard let snapshot = await storage.loadAccountSnapshot(for: accountIndex) else { return .init() }
        return snapshot.transactionLedger.entries
    }
    
    public func loadTransactionMetadata(for transactionHash: Transaction.Hash,
                                        using storage: Storage) async -> Storage.AccountSnapshot.TransactionLedger.Entry? {
        let accountIndex = account.unhardenedIndex
        return await storage.loadLedgerEntry(for: transactionHash.naturalOrder, accountIndex: accountIndex)
    }
    
    public func updateTransactionLabel(for transactionHash: Transaction.Hash,
                                       to label: String?,
                                       using storage: Storage) async throws -> Bool {
        try await updateLedgerEntry(for: transactionHash, using: storage) { entry in
            entry.label = label
        }
    }
    
    public func updateTransactionMemo(for transactionHash: Transaction.Hash,
                                      to memo: String?,
                                      using storage: Storage) async throws -> Bool {
        try await updateLedgerEntry(for: transactionHash, using: storage) { entry in
            entry.memo = memo
        }
    }
    
    public func updateTransactionMetadata(for transactionHash: Transaction.Hash,
                                          label: String?,
                                          memo: String?,
                                          using storage: Storage) async throws -> Bool {
        try await updateLedgerEntry(for: transactionHash, using: storage) { entry in
            entry.label = label
            entry.memo = memo
        }
    }
    
    public func loadFeePreference() async throws -> Wallet.FeePolicy.Preference {
        do {
            if let storedPreference = try await storageSettings.loadFeePreference(for: account.unhardenedIndex) {
                return storedPreference
            }
            return .standard
        } catch {
            throw Error.feePreferenceUnavailable(error)
        }
    }
    
    public func updateFeePreference(_ preference: Wallet.FeePolicy.Preference) async throws {
        do {
            try await storageSettings.updateFeePreference(preference, for: account.unhardenedIndex)
        } catch {
            throw Error.feePreferenceUnavailable(error)
        }
    }
}

extension Account {
    func updateLedgerEntry(for transactionHash: Transaction.Hash,
                           using storage: Storage,
                           applying transform: (inout Storage.AccountSnapshot.TransactionLedger.Entry) -> Void) async throws -> Bool {
        let accountIndex = account.unhardenedIndex
        guard var entry = await storage.loadLedgerEntry(for: transactionHash.naturalOrder, accountIndex: accountIndex) else {
            return false
        }
        
        let originalEntry = entry
        transform(&entry)
        guard entry != originalEntry else { return true }
        
        return try await storage.updateLedgerEntry(entry, for: accountIndex)
    }
}
