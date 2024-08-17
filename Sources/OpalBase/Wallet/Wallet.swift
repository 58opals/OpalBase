import Foundation

struct Wallet {
    let mnemonic: Mnemonic
    
    private let purpose: DerivationPath.Purpose
    private let coinType: DerivationPath.CoinType
    
    private(set) var accounts: [Account]
    
    init(mnemonic: Mnemonic,
         purpose: DerivationPath.Purpose = .bip44,
         coinType: DerivationPath.CoinType = .bitcoinCash) {
        self.mnemonic = mnemonic
        self.purpose = purpose
        self.coinType = coinType
        self.accounts = []
    }
}
 
extension Wallet {
    mutating func addAccount(unhardenedIndex: UInt32, fulcrumServerURL: String? = nil) async throws {
        let derivationPathAccount = DerivationPath.Account(unhardenedIndex: unhardenedIndex)
        
        let rootExtendedKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        let account = try await Account(fulcrumServerURL: fulcrumServerURL,
                                        rootExtendedKey: rootExtendedKey,
                                        purpose: purpose,
                                        coinType: coinType,
                                        account: derivationPathAccount)
        self.accounts.append(account)
    }
    
    func getAccount(unhardenedIndex: Int) throws -> Account {
        guard unhardenedIndex < accounts.count else { throw Error.cannotGetAccount(index: unhardenedIndex) }
        return accounts[unhardenedIndex]
    }
}

extension Wallet {
    enum Error: Swift.Error {
        case cannotGetAccount(index: Int)
    }
}

extension Wallet {
    func getBalance() throws -> Satoshi {
        var totalBalance: Satoshi = try Satoshi(0)
        for account in accounts {
            let balance = try account.addressBook.getBalanceFromCache()
            totalBalance = try totalBalance + balance
        }
        return totalBalance
    }
}
