// WalletActor+Error.swift

import Foundation

public actor WalletActor: Identifiable {
    public let mnemonic: MnemonicModel
    public let tokenMetadataStore: TokenMetadataRepository
    
    let purpose: DerivationPathModel.PurposeModel
    let coinType: DerivationPathModel.CoinTypeModel
    
    public let id: Data
    
    var accounts: [UInt32: AccountActor] = .init()
    
    public init(mnemonic: MnemonicModel,
                purpose: DerivationPathModel.PurposeModel = .bip44,
                coinType: DerivationPathModel.CoinTypeModel = .bitcoinCash) {
        self.mnemonic = mnemonic
        self.tokenMetadataStore = TokenMetadataRepository()
        self.purpose = purpose
        self.coinType = coinType
        self.id = [self.mnemonic.seed, self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data].generateID()
    }
    
    public init(from snapshot: WalletActor.SnapshotModel) async throws {
        self.mnemonic = try MnemonicModel(words: snapshot.words, passphrase: snapshot.passphrase)
        self.tokenMetadataStore = TokenMetadataRepository()
        self.purpose = snapshot.purpose
        self.coinType = snapshot.coinType
        self.id = [self.mnemonic.seed, self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data].generateID()
        
        let rootExtendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: try .init(seed: self.mnemonic.seed))
        for accountSnap in snapshot.accounts {
            let account = try await AccountActor(from: accountSnap,
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

extension WalletActor {
    public enum Error: Swift.Error, Equatable {
        case snapshotDoesNotMatchWallet
        case cannotFetchAccount(index: UInt32)
    }
}

extension WalletActor: Equatable {
    public static func == (lhs: WalletActor, rhs: WalletActor) -> Bool {
        lhs.id == rhs.id
    }
}

extension WalletActor {
    public func addAccount(unhardenedIndex: UInt32) async throws {
        let derivationPathAccount = try DerivationPathModel.AccountActor(rawIndexInteger: unhardenedIndex)
        
        let rootExtendedPrivateKey = PrivateKeyModel.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        let account = try await AccountActor(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                        purpose: purpose,
                                        coinType: coinType,
                                        account: derivationPathAccount)
        let index = await account.unhardenedIndex
        self.accounts[index] = account
    }
}

extension WalletActor {
    public var numberOfAccounts: Int { self.accounts.count }
    func updateAccounts(_ accounts: [AccountActor]) async {
        var updatedAccounts: [UInt32: AccountActor] = .init(minimumCapacity: accounts.count)
        for account in accounts {
            let index = await account.unhardenedIndex
            updatedAccounts[index] = account
        }
        self.accounts = updatedAccounts
    }
}

extension WalletActor {
    public var derivationPath: (purpose: DerivationPathModel.PurposeModel, coinType: DerivationPathModel.CoinTypeModel) {
        return (self.purpose, self.coinType)
    }
    
    public func fetchAccount(at unhardenedIndex: UInt32) async throws -> AccountActor {
        guard let account = accounts[unhardenedIndex] else {
            throw Error.cannotFetchAccount(index: unhardenedIndex)
        }
        
        return account
    }
}

extension WalletActor {
    public func calculateCachedBalance() async throws -> SatoshiModel {
        var totalBalance: SatoshiModel = .init()
        for account in accounts.values {
            let balance = try await account.addressBook.calculateCachedTotalBalance()
            totalBalance = try totalBalance + balance
        }
        
        return totalBalance
    }
    
    public func calculateBalance(loader: @escaping @Sendable (AddressModel) async throws -> SatoshiModel) async throws -> SatoshiModel {
        guard !accounts.isEmpty else { return try SatoshiModel(0) }
        
        let total: SatoshiModel = try await withThrowingTaskGroup(of: SatoshiModel.self) { group in
            for account in accounts.values {
                group.addTask {
                    let refresh = try await account.refreshBalances(loader: loader)
                    return refresh.total
                }
            }
            
            var aggregate: SatoshiModel = .init()
            for try await partial in group {
                aggregate = try aggregate + partial
            }
            
            return aggregate
        }
        
        return total
    }
}

