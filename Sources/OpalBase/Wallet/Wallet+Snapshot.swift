// Wallet+Snapshot.swift

import Foundation
import CryptoKit

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

extension Wallet.Snapshot {
    enum Error: Swift.Error {
        case missingCombinedData
    }
}

extension Wallet.Snapshot: Sendable {}

extension Wallet {
    public func makeSnapshot() async -> Snapshot {
        var accountSnaps: [Account.Snapshot] = .init()
        for account in accounts {
            let snap = await account.getSnapshot()
            accountSnaps.append(snap)
        }
        return Snapshot(words: mnemonic.words,
                        passphrase: mnemonic.passphrase,
                        purpose: purpose,
                        coinType: coinType,
                        accounts: accountSnaps)
    }
    
    public func saveSnapshot(to url: URL, using key: SymmetricKey? = nil) async throws {
        let data = try JSONEncoder().encode(await makeSnapshot())
        let output: Data
        if let key {
            let sealed = try AES.GCM.seal(data, using: key)
            guard let combined = sealed.combined else { throw Snapshot.Error.missingCombinedData }
            output = combined
        } else {
            output = data
        }
        try output.write(to: url)
    }
    
    public func loadSnapshot(from url: URL, using key: SymmetricKey? = nil) async throws {
        let data = try Data(contentsOf: url)
        let input: Data
        if let key {
            let sealed = try AES.GCM.SealedBox(combined: data)
            input = try AES.GCM.open(sealed, using: key)
        } else {
            input = data
        }
        let snap = try JSONDecoder().decode(Snapshot.self, from: input)
        
        self.accounts.removeAll()
        let rootKey = PrivateKey.Extended(rootKey: try .init(seed: mnemonic.seed))
        for accSnap in snap.accounts {
            let account = try await Account(fulcrumServerURLs: [],
                                            rootExtendedPrivateKey: rootKey,
                                            purpose: accSnap.purpose,
                                            coinType: accSnap.coinType,
                                            account: try DerivationPath.Account(rawIndexInteger: accSnap.account))
            try await account.applySnapshot(accSnap)
            self.accounts.append(account)
        }
    }
}
