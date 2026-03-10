// OpalBase+Wallet+Snapshot.swift

import Foundation
import OpalCrypto

extension _OpalBase.Wallet {
    public struct Snapshot: Codable {
        public let words: [String]
        public let passphrase: String
        public let purpose: OpalBase.DerivationPath.Purpose
        public let coinType: OpalBase.DerivationPath.CoinType
        public let accounts: [OpalBase.Account.Snapshot]
        public let tokenMetadata: OpalBase.CashTokens.MetadataRepository.Snapshot?
        
        public init(words: [String],
                    passphrase: String,
                    purpose: OpalBase.DerivationPath.Purpose,
                    coinType: OpalBase.DerivationPath.CoinType,
                    accounts: [OpalBase.Account.Snapshot],
                    tokenMetadata: OpalBase.CashTokens.MetadataRepository.Snapshot? = nil) {
            self.words = words
            self.passphrase = passphrase
            self.purpose = purpose
            self.coinType = coinType
            self.accounts = accounts
            self.tokenMetadata = tokenMetadata
        }
    }
}

extension _OpalBase.Wallet.Snapshot: Sendable {}

extension _OpalBase.Wallet {
    public func makeSnapshot() async -> Snapshot {
        var accountSnaps: [OpalBase.Account.Snapshot] = .init()
        for (_, account) in accounts.sorted(by: { $0.key < $1.key }) {
            let snap = await account.makeSnapshot()
            accountSnaps.append(snap)
        }
        let tokenMetadata = await tokenMetadataStore.snapshot()
        return Snapshot(words: mnemonic.words.map(\.text),
                        passphrase: passphrase,
                        purpose: purpose,
                        coinType: coinType,
                        accounts: accountSnaps,
                        tokenMetadata: tokenMetadata)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) async throws {
        guard snapshot.words == mnemonic.words.map(\.text),
              snapshot.passphrase == passphrase,
              snapshot.purpose == purpose,
              snapshot.coinType == coinType else {
            throw Error.snapshotDoesNotMatchWallet
        }
        
        var updatedAccounts: [UInt32: OpalBase.Account] = .init(minimumCapacity: snapshot.accounts.count)
        for accountSnap in snapshot.accounts {
            guard accountSnap.purpose == purpose,
                  accountSnap.coinType == coinType else {
                throw Error.snapshotDoesNotMatchWallet
            }
            let account = try await OpalBase.Account(from: accountSnap,
                                            rootExtendedPrivateKey: rootExtendedPrivateKey,
                                            purpose: purpose,
                                            coinType: coinType)
            let index = await account.unhardenedIndex
            updatedAccounts[index] = account
        }
        self.accounts = updatedAccounts
        
        let tokenMetadata = snapshot.tokenMetadata ?? .init(byCategory: .init())
        await tokenMetadataStore.applySnapshot(tokenMetadata)
    }
}
