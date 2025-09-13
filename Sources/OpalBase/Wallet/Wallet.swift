// Wallet.swift

import Foundation

public actor Wallet: Identifiable {
    public let mnemonic: Mnemonic
    
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    
    public let id: Data
    
    var accounts: [Account] = .init()
    
    private func generateID(from inputs: [Data]) -> Data {
        var hashInput: Data = .init()
        for input in inputs {
            hashInput.append(input)
        }
        let sha256Hash = SHA256.hash(hashInput)
        return sha256Hash
    }
    
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
        
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: self.mnemonic.seed))
        for accountSnap in snapshot.accounts {
            let account = try await Account(from: accountSnap,
                                            rootExtendedPrivateKey: rootExtendedPrivateKey,
                                            purpose: snapshot.purpose,
                                            coinType: snapshot.coinType)
            self.accounts.append(account)
        }
        
        self.id = [self.mnemonic.seed, self.purpose.hardenedIndex.data, self.coinType.hardenedIndex.data].generateID()
    }
}

extension Wallet {
    public enum Error: Swift.Error {
        case cannotGetAccount(index: UInt32)
    }
}

extension Wallet: Equatable {
    public static func == (lhs: Wallet, rhs: Wallet) -> Bool {
        lhs.id == rhs.id
    }
}

extension Wallet {
    public func addAccount(unhardenedIndex: UInt32, fulcrumServerURLs: [String] = []) async throws {
        let derivationPathAccount = try DerivationPath.Account(rawIndexInteger: unhardenedIndex)
        
        let rootExtendedPrivateKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let account = try await Account(fulcrumServerURLs: fulcrumServerURLs,
                                        rootExtendedPrivateKey: rootExtendedPrivateKey,
                                        purpose: purpose,
                                        coinType: coinType,
                                        account: derivationPathAccount)
        self.accounts.append(account)
    }
}

extension Wallet {
    public var numberOfAccounts: Int { self.accounts.count }
    public func setAccounts(_ accounts: [Account]) {
        self.accounts = accounts
    }
}

extension Wallet {
    public func observeNetworkStatus(forAccount index: UInt32) async throws -> AsyncStream<Network.Wallet.Status> {
        let account = try fetchAccount(at: index)
        return await account.observeNetworkStatus()
    }
    
    public func processQueuedRequests(forAccount index: UInt32) async throws {
        let account = try fetchAccount(at: index)
        await account.processQueuedRequests()
    }
}

extension Wallet {
    public var derivationPath: (purpose: DerivationPath.Purpose, coinType: DerivationPath.CoinType) {
        return (self.purpose, self.coinType)
    }
    
    public func fetchAccount(at unhardenedIndex: UInt32) throws -> Account {
        guard Int(unhardenedIndex) < accounts.count else { throw Error.cannotGetAccount(index: unhardenedIndex) }
        return accounts[Int(unhardenedIndex)]
    }
}

extension Wallet {
    public func calculateCachedBalance() async throws -> Satoshi {
        var totalBalance: Satoshi = .init()
        for account in accounts {
            let balance = try await account.addressBook.calculateCachedTotalBalance()
            totalBalance = try totalBalance + balance
        }
        
        return totalBalance
    }
    
    public func calculateBalance() async throws -> Satoshi {
        guard !accounts.isEmpty else { return try Satoshi(0) }
        
        let total: UInt64 = try await withThrowingTaskGroup(of: UInt64.self) { group in
            for account in accounts {
                group.addTask {
                    try await account.calculateBalance().uint64
                }
            }
            
            var aggregate: UInt64 = 0
            for try await partial in group {
                aggregate += partial
            }
            
            return aggregate
        }
        
        return try Satoshi(total)
    }
}
