// Wallet.swift

import Foundation

public actor Wallet: Identifiable {
    public let mnemonic: Mnemonic
    public let passphrase: String
    
    private let purpose: DerivationPath.Purpose
    private let coinType: DerivationPath.CoinType
    
    public let id: Data
    
    private(set) var accounts: [Account] = .init()
    
    public init(mnemonic: Mnemonic,
                purpose: DerivationPath.Purpose = .bip44,
                coinType: DerivationPath.CoinType = .bitcoinCash) {
        self.mnemonic = mnemonic
        self.passphrase = mnemonic.passphrase
        self.purpose = purpose
        self.coinType = coinType
        
        var hashInput: Data = .init()
        hashInput.append(mnemonic.seed)
        hashInput.append(purpose.hardenedIndex.data)
        hashInput.append(coinType.hardenedIndex.data)
        let sha256Hash = SHA256.hash(hashInput)
        self.id = sha256Hash
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
    public func getDerivationPath() -> (purpose: DerivationPath.Purpose, coinType: DerivationPath.CoinType) {
        return (self.purpose, self.coinType)
    }
    
    public func getAccount(unhardenedIndex: UInt32) throws -> Account {
        guard Int(unhardenedIndex) < accounts.count else { throw Error.cannotGetAccount(index: unhardenedIndex) }
        return accounts[Int(unhardenedIndex)]
    }
}

extension Wallet {
    public func getBalance() async throws -> Satoshi {
        var totalBalance: Satoshi = .init()
        for account in accounts {
            let balance = try await account.addressBook.getTotalBalanceFromCache()
            totalBalance = try totalBalance + balance
        }
        
        return totalBalance
    }
    
    public func calculateBalance() async throws -> Satoshi {
        var totalBalance: UInt64 = 0
        
        for accountIndex in 0..<self.accounts.count {
            let balanceFromBlockchain = try await self.accounts[accountIndex].calculateBalance().uint64
            totalBalance += balanceFromBlockchain
        }
        
        return try Satoshi(totalBalance)
    }
}
