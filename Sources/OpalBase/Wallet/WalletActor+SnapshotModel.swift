// WalletActor+SnapshotModel.swift

import Foundation

extension WalletActor {
    public struct SnapshotModel: Codable {
        public let words: [String]
        public let passphrase: String
        public let purpose: DerivationPathModel.PurposeModel
        public let coinType: DerivationPathModel.CoinTypeModel
        public let accounts: [AccountActor.SnapshotModel]
        public let tokenMetadata: TokenMetadataRepository.SnapshotModel?
        
        public init(words: [String],
                    passphrase: String,
                    purpose: DerivationPathModel.PurposeModel,
                    coinType: DerivationPathModel.CoinTypeModel,
                    accounts: [AccountActor.SnapshotModel],
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

extension WalletActor.SnapshotModel: Sendable {}

extension WalletActor {
    public func makeSnapshot() async -> SnapshotModel {
        var accountSnaps: [AccountActor.SnapshotModel] = .init()
        for (_, account) in accounts.sorted(by: { $0.key < $1.key }) {
            let snap = await account.makeSnapshot()
            accountSnaps.append(snap)
        }
        let tokenMetadata = await tokenMetadataStore.snapshot()
        return SnapshotModel(words: mnemonic.words,
                        passphrase: mnemonic.passphrase,
                        purpose: purpose,
                        coinType: coinType,
                        accounts: accountSnaps,
                        tokenMetadata: tokenMetadata)
    }
    
    public func applySnapshot(_ snapshot: SnapshotModel) async throws {
        guard snapshot.words == mnemonic.words,
              snapshot.passphrase == mnemonic.passphrase,
              snapshot.purpose == purpose,
              snapshot.coinType == coinType else {
            throw Error.snapshotDoesNotMatchWallet
        }
        
        let rootKey = PrivateKeyModel.ExtendedModel(rootKey: try .init(seed: mnemonic.seed))
        var updatedAccounts: [UInt32: AccountActor] = .init(minimumCapacity: snapshot.accounts.count)
        for accountSnap in snapshot.accounts {
            guard accountSnap.purpose == purpose,
                  accountSnap.coinType == coinType else {
                throw Error.snapshotDoesNotMatchWallet
            }
            let account = try await AccountActor(from: accountSnap,
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
