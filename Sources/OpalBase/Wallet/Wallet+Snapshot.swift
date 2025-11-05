// Wallet+Snapshot.swift

import Foundation

extension Wallet {
    public struct Snapshot: Codable {
        public let words: [String]
        public let passphrase: String
        public let purpose: DerivationPath.Purpose
        public let coinType: DerivationPath.CoinType
        public let accounts: [Account.Snapshot]
        
        public init(words: [String],
                    passphrase: String,
                    purpose: DerivationPath.Purpose,
                    coinType: DerivationPath.CoinType,
                    accounts: [Account.Snapshot]) {
            self.words = words
            self.passphrase = passphrase
            self.purpose = purpose
            self.coinType = coinType
            self.accounts = accounts
        }
    }
}

extension Wallet.Snapshot: Sendable {}

extension Wallet {
    public func makeSnapshot() async -> Snapshot {
        var accountSnaps: [Account.Snapshot] = .init()
        for (_, account) in accounts.sorted(by: { $0.key < $1.key }) {
            let snap = await account.makeSnapshot()
            accountSnaps.append(snap)
        }
        return Snapshot(words: mnemonic.words,
                        passphrase: mnemonic.passphrase,
                        purpose: purpose,
                        coinType: coinType,
                        accounts: accountSnaps)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) async throws {
        self.accounts.removeAll()
        let rootKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        for accountSnap in snapshot.accounts {
            let account = try await Account(from: accountSnap,
                                            rootExtendedPrivateKey: rootKey,
                                            purpose: accountSnap.purpose,
                                            coinType: accountSnap.coinType)
            let index = await account.unhardenedIndex
            self.accounts[index] = account
        }
    }
}
