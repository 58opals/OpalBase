// AccountActor+.swift

import Foundation

public actor AccountActor: Identifiable {
    private let rootExtendedPrivateKey: PrivateKeyModel.ExtendedModel
    
    let purpose: DerivationPathModel.PurposeModel
    let coinType: DerivationPathModel.CoinTypeModel
    let account: DerivationPathModel.AccountActor
    
    public let id: Data
    public let addressBook: AddressModel.BookActor
    
    let privacyShaper: PrivacyShaperActor
    public let privacyConfiguration: PrivacyShaperActor.Configuration
    
    init(rootExtendedPrivateKey: PrivateKeyModel.ExtendedModel,
         purpose: DerivationPathModel.PurposeModel,
         coinType: DerivationPathModel.CoinTypeModel,
         account: DerivationPathModel.AccountActor,
         addressBook: AddressModel.BookActor,
         privacyConfiguration: PrivacyShaperActor.Configuration = .standard) throws {
        self.rootExtendedPrivateKey = rootExtendedPrivateKey
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        
        self.id = try [self.rootExtendedPrivateKey.serialize(), self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data, self.account.deriveHardenedIndex().data].generateID()
        self.addressBook = addressBook
        self.privacyConfiguration = privacyConfiguration
        self.privacyShaper = .init(configuration: privacyConfiguration)
    }
    
    init(rootExtendedPrivateKey: PrivateKeyModel.ExtendedModel,
         purpose: DerivationPathModel.PurposeModel,
         coinType: DerivationPathModel.CoinTypeModel,
         account: DerivationPathModel.AccountActor,
         privacyConfiguration: PrivacyShaperActor.Configuration = .standard) async throws {
        let addressBook = try await AddressModel.BookActor(rootExtendedPrivateKey: rootExtendedPrivateKey,
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
    
    init(from snapshot: AccountActor.SnapshotModel,
         rootExtendedPrivateKey: PrivateKeyModel.ExtendedModel,
         purpose: DerivationPathModel.PurposeModel,
         coinType: DerivationPathModel.CoinTypeModel,
         privacyConfiguration: PrivacyShaperActor.Configuration = .standard) async throws {
        let accountPath = try DerivationPathModel.AccountActor(rawIndexInteger: snapshot.accountUnhardenedIndex)
        let addressBook = try await AddressModel.BookActor(from: snapshot.addressBook,
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

extension AccountActor: Equatable {
    public static func == (lhs: AccountActor, rhs: AccountActor) -> Bool {
        lhs.id == rhs.id
    }
}

extension AccountActor {
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

extension AccountActor {
    public var derivationPath: (purpose: DerivationPathModel.PurposeModel,
                                coinType: DerivationPathModel.CoinTypeModel,
                                account: DerivationPathModel.AccountActor) {
        return (self.purpose, self.coinType, self.account)
    }
}

extension AccountActor {
    public func loadBalanceFromCache() async throws -> SatoshiModel {
        try await addressBook.calculateCachedTotalBalance()
    }
}

extension AccountActor {
    public func loadTransactionHistory() async -> [TransactionModel.HistoryModel.RecordModel] {
        await listTransactions()
    }
}

// MARK: - AddressModel BookActor Accessors
extension AccountActor {
    public func listEntries(for usage: DerivationPathModel.UsageModel) async -> [AddressModel.BookActor.EntryModel] {
        await addressBook.listEntries(for: usage)
    }
    
    public func selectNextEntry(for usage: DerivationPathModel.UsageModel) async throws -> AddressModel.BookActor.EntryModel {
        try await addressBook.selectNextEntry(for: usage)
    }
    
    public func readGapLimit() async -> Int {
        await addressBook.readGapLimit()
    }
}

