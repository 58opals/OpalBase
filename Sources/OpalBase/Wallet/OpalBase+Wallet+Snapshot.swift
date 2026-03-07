// OpalBase.Wallet+Snapshot.swift

import Foundation

extension _OpalBase.Wallet {
    public struct Snapshot: Codable {
        public let words: [String]
        public let passphrase: String
        public let purpose: OpalBase.DerivationPath.PurposeModel
        public let coinType: OpalBase.DerivationPath.CoinTypeModel
        public let accounts: [OpalBase.Account.SnapshotModel]
        public let tokenMetadata: TokenMetadataRepository.SnapshotModel?
        
        public init(words: [String],
                    passphrase: String,
                    purpose: OpalBase.DerivationPath.PurposeModel,
                    coinType: OpalBase.DerivationPath.CoinTypeModel,
                    accounts: [OpalBase.Account.SnapshotModel],
                    tokenMetadata: TokenMetadataRepository.SnapshotModel? = nil) {
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
        var accountSnaps: [OpalBase.Account.SnapshotModel] = .init()
        for (_, account) in accounts.sorted(by: { $0.key < $1.key }) {
            let snap = await account.makeSnapshot()
            accountSnaps.append(snap)
        }
        let tokenMetadata = await tokenMetadataStore.snapshot()
        return Snapshot(words: mnemonic.words,
                        passphrase: mnemonic.passphrase,
                        purpose: purpose,
                        coinType: coinType,
                        accounts: accountSnaps,
                        tokenMetadata: tokenMetadata)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) async throws {
        guard snapshot.words == mnemonic.words,
              snapshot.passphrase == mnemonic.passphrase,
              snapshot.purpose == purpose,
              snapshot.coinType == coinType else {
            throw Error.snapshotDoesNotMatchWallet
        }
        
        let rootKey = OpalBase.PrivateKey.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        var updatedAccounts: [UInt32: OpalBase.Account] = .init(minimumCapacity: snapshot.accounts.count)
        for accountSnap in snapshot.accounts {
            guard accountSnap.purpose == purpose,
                  accountSnap.coinType == coinType else {
                throw Error.snapshotDoesNotMatchWallet
            }
            let account = try await OpalBase.Account(from: accountSnap,
                                            rootExtendedPrivateKey: rootKey,
                                            purpose: purpose,
                                            coinType: coinType)
            let index = await account.unhardenedIndex
            updatedAccounts[index] = account
        }
        self.accounts = updatedAccounts
        
        if let tokenMetadata = snapshot.tokenMetadata {
            await tokenMetadataStore.applySnapshot(tokenMetadata)
        }
    }
}
