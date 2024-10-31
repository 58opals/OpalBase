import Foundation

public struct Wallet {
    public let mnemonic: Mnemonic
    
    private let purpose: DerivationPath.Purpose
    private let coinType: DerivationPath.CoinType
    
    private(set) var accounts: [Account] = .init()
    
    public init(mnemonic: Mnemonic,
                purpose: DerivationPath.Purpose = .bip44,
                coinType: DerivationPath.CoinType = .bitcoinCash) {
        self.mnemonic = mnemonic
        self.purpose = purpose
        self.coinType = coinType
    }
}

extension Wallet {
    public mutating func addAccount(unhardenedIndex: UInt32, fulcrumServerURL: String? = nil) async throws {
        let derivationPathAccount = DerivationPath.Account(unhardenedIndex: unhardenedIndex)
        
        let rootExtendedKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let account = try await Account(fulcrumServerURL: fulcrumServerURL,
                                  rootExtendedKey: rootExtendedKey,
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
    
    public mutating func calculateBalance() async throws -> Satoshi {
        var totalBalance: UInt64 = 0
        
        for accountIndex in 0..<self.accounts.count {
            let balanceFromBlockchain = try await self.accounts[accountIndex].calculateBalance().uint64
            totalBalance += balanceFromBlockchain
        }
        
        return try Satoshi(totalBalance)
    }
}

