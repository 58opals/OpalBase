import Foundation

struct Wallet {
    let mnemonic: Mnemonic
    let purpose: DerivationPath.Purpose
    let coinType: DerivationPath.CoinType
    private(set) var accounts: [Account]
    
    init(mnemonic: Mnemonic, purpose: DerivationPath.Purpose = .bip44, coinType: DerivationPath.CoinType = .bitcoinCash) {
        self.mnemonic = mnemonic
        self.purpose = purpose
        self.coinType = coinType
        self.accounts = []
    }
    
    mutating func addAccount(index: UInt32) async throws {
        let rootKey = try PrivateKey.Extended.Root(seed: mnemonic.seed)
        let extendedKey = try PrivateKey.Extended(rootKey: rootKey)
            .deriveChildPrivateKey(at: purpose.index)
            .deriveChildPrivateKey(at: coinType.index)
            .deriveChildPrivateKey(at: index | 0x80000000)
        
        let account = try await Account(extendedKey: extendedKey, accountIndex: index)
        self.accounts.append(account)
    }
    
    func getAccount(index: Int) -> Account? {
        guard index < accounts.count else { return nil }
        return accounts[index]
    }
}
