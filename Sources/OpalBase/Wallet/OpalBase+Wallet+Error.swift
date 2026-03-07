// OpalBase+Wallet+Error.swift

import Foundation

extension OpalBase {
    public actor Wallet: Identifiable {
    public let mnemonic: OpalBase.Mnemonic
    public let tokenMetadataStore: TokenMetadataRepository
    
    let purpose: OpalBase.DerivationPath.PurposeModel
    let coinType: OpalBase.DerivationPath.CoinTypeModel
    
    public let id: Data
    
    var accounts: [UInt32: OpalBase.Account] = .init()
    
    public init(mnemonic: OpalBase.Mnemonic,
                purpose: OpalBase.DerivationPath.PurposeModel = .bip44,
                coinType: OpalBase.DerivationPath.CoinTypeModel = .bitcoinCash) {
        self.mnemonic = mnemonic
        self.tokenMetadataStore = TokenMetadataRepository()
        self.purpose = purpose
        self.coinType = coinType
        self.id = [self.mnemonic.seed, self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data].generateID()
    }
    
    public init(from snapshot: OpalBase.Wallet.Snapshot) async throws {
        self.mnemonic = try OpalBase.Mnemonic(words: snapshot.words, passphrase: snapshot.passphrase)
        self.tokenMetadataStore = TokenMetadataRepository()
        self.purpose = snapshot.purpose
        self.coinType = snapshot.coinType
        self.id = [self.mnemonic.seed, self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data].generateID()
        
        let rootExtendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: try .init(seed: self.mnemonic.seed))
        for accountSnap in snapshot.accounts {
            let account = try await OpalBase.Account(from: accountSnap,
                                            rootExtendedPrivateKey: rootExtendedPrivateKey,
                                            purpose: snapshot.purpose,
                                            coinType: snapshot.coinType)
            let index = await account.unhardenedIndex
            self.accounts[index] = account
        }
        
        if let tokenMetadata = snapshot.tokenMetadata {
            await self.tokenMetadataStore.applySnapshot(tokenMetadata)
        }
    }
    }
}

extension _OpalBase.Wallet {
    public enum Error: Swift.Error, Equatable {
        case snapshotDoesNotMatchWallet
        case cannotFetchAccount(index: UInt32)
    }
}

extension _OpalBase.Wallet: Equatable {
    public static func == (lhs: OpalBase.Wallet, rhs: OpalBase.Wallet) -> Bool {
        lhs.id == rhs.id
    }
}

extension _OpalBase.Wallet {
    public func addAccount(unhardenedIndex: UInt32) async throws {
        let derivationPathAccount = try OpalBase.DerivationPath.Account(rawIndexInteger: unhardenedIndex)
        
        let rootExtendedPrivateKey = OpalBase.PrivateKey.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        let account = try await OpalBase.Account(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                        purpose: purpose,
                                        coinType: coinType,
                                        account: derivationPathAccount)
        let index = await account.unhardenedIndex
        self.accounts[index] = account
    }
}

extension _OpalBase.Wallet {
    public var numberOfAccounts: Int { self.accounts.count }
    func updateAccounts(_ accounts: [OpalBase.Account]) async {
        var updatedAccounts: [UInt32: OpalBase.Account] = .init(minimumCapacity: accounts.count)
        for account in accounts {
            let index = await account.unhardenedIndex
            updatedAccounts[index] = account
        }
        self.accounts = updatedAccounts
    }
}

extension _OpalBase.Wallet {
    public var derivationPath: (purpose: OpalBase.DerivationPath.PurposeModel, coinType: OpalBase.DerivationPath.CoinTypeModel) {
        return (self.purpose, self.coinType)
    }
    
    public func fetchAccount(at unhardenedIndex: UInt32) async throws -> OpalBase.Account {
        guard let account = accounts[unhardenedIndex] else {
            throw Error.cannotFetchAccount(index: unhardenedIndex)
        }
        
        return account
    }
}

extension _OpalBase.Wallet {
    public func calculateCachedBalance() async throws -> OpalBase.Satoshi {
        var totalBalance: OpalBase.Satoshi = .init()
        for account in accounts.values {
            let balance = try await account.addressBook.calculateCachedTotalBalance()
            totalBalance = try totalBalance + balance
        }
        
        return totalBalance
    }
    
    public func calculateBalance(loader: @escaping @Sendable (OpalBase.Address) async throws -> OpalBase.Satoshi) async throws -> OpalBase.Satoshi {
        guard !accounts.isEmpty else { return try OpalBase.Satoshi(0) }
        
        let total: OpalBase.Satoshi = try await withThrowingTaskGroup(of: OpalBase.Satoshi.self) { group in
            for account in accounts.values {
                group.addTask {
                    let refresh = try await account.refreshBalances(loader: loader)
                    return refresh.total
                }
            }
            
            var aggregate: OpalBase.Satoshi = .init()
            for try await partial in group {
                aggregate = try aggregate + partial
            }
            
            return aggregate
        }
        
        return total
    }
}
