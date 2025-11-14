// Wallet.swift

import Foundation

public actor Wallet: Identifiable {
    public let mnemonic: Mnemonic
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    
    public let id: Data
    
    var accounts: [UInt32: Account] = .init()
    
    public init(mnemonic: Mnemonic,
                purpose: DerivationPath.Purpose = .bip44,
                coinType: DerivationPath.CoinType = .bitcoinCash) {
        self.mnemonic = mnemonic
        self.purpose = purpose
        self.coinType = coinType
        self.id = [self.mnemonic.seed, self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data].generateID()
    }
    
    public init(from snapshot: Wallet.Snapshot) async throws {
        self.mnemonic = try Mnemonic(words: snapshot.words, passphrase: snapshot.passphrase)
        self.purpose = snapshot.purpose
        self.coinType = snapshot.coinType
        self.id = [self.mnemonic.seed, self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data].generateID()
        
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: self.mnemonic.seed))
        for accountSnap in snapshot.accounts {
            let account = try await Account(from: accountSnap,
                                            rootExtendedPrivateKey: rootExtendedPrivateKey,
                                            purpose: snapshot.purpose,
                                            coinType: snapshot.coinType)
            let index = await account.unhardenedIndex
            self.accounts[index] = account
        }
    }
}

extension Wallet {
    public enum Error: Swift.Error, Equatable {
        case snapshotDoesNotMatchWallet
        case cannotFetchAccount(index: UInt32)
    }
}

extension Wallet: Equatable {
    public static func == (lhs: Wallet, rhs: Wallet) -> Bool {
        lhs.id == rhs.id
    }
}

extension Wallet {
    public func addAccount(unhardenedIndex: UInt32) async throws {
        let derivationPathAccount = try DerivationPath.Account(rawIndexInteger: unhardenedIndex)
        
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let account = try await Account(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                        purpose: purpose,
                                        coinType: coinType,
                                        account: derivationPathAccount)
        let index = await account.unhardenedIndex
        self.accounts[index] = account
    }
}

extension Wallet {
    public var numberOfAccounts: Int { self.accounts.count }
    public func updateAccounts(_ accounts: [Account]) async {
        var updatedAccounts: [UInt32: Account] = .init(minimumCapacity: accounts.count)
        for account in accounts {
            let index = await account.unhardenedIndex
            updatedAccounts[index] = account
        }
        self.accounts = updatedAccounts
    }
}

extension Wallet {
    public var derivationPath: (purpose: DerivationPath.Purpose, coinType: DerivationPath.CoinType) {
        return (self.purpose, self.coinType)
    }
    
    public func fetchAccount(at unhardenedIndex: UInt32) async throws -> Account {
        guard let account = accounts[unhardenedIndex] else {
            throw Error.cannotFetchAccount(index: unhardenedIndex)
        }
        
        return account
    }
}

extension Wallet {
    public func calculateCachedBalance() async throws -> Satoshi {
        var totalBalance: Satoshi = .init()
        for account in accounts.values {
            let balance = try await account.addressBook.calculateCachedTotalBalance()
            totalBalance = try totalBalance + balance
        }
        
        return totalBalance
    }
    
    public func calculateBalance(loader: @escaping @Sendable (Address) async throws -> Satoshi) async throws -> Satoshi {
        guard !accounts.isEmpty else { return try Satoshi(0) }
        
        let total: UInt64 = try await withThrowingTaskGroup(of: UInt64.self) { group in
            for account in accounts.values {
                group.addTask {
                    let refresh = try await account.refreshBalances(loader: loader)
                    return refresh.total.uint64
                }
            }
            
            var aggregate: UInt64 = 0
            for try await partial in group {
                let (updated, didOverflow) = aggregate.addingReportingOverflow(partial)
                if didOverflow { throw Satoshi.Error.exceedsMaximumAmount }
                aggregate = updated
            }
            
            return aggregate
        }
        
        return try Satoshi(total)
    }
}
