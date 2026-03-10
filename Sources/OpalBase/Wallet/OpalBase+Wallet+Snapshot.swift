// OpalBase+Wallet+Snapshot.swift

import Foundation
import OpalCrypto

extension _OpalBase.Wallet {
    public struct Snapshot: Codable {
        public let purpose: OpalBase.Key.DerivationPath.Purpose
        public let coinType: OpalBase.Key.DerivationPath.CoinType
        public let accounts: [OpalBase.Account.Snapshot]
        public let tokenMetadata: OpalBase.CashTokens.MetadataRepository.Snapshot?
        
        public init(purpose: OpalBase.Key.DerivationPath.Purpose,
                    coinType: OpalBase.Key.DerivationPath.CoinType,
                    accounts: [OpalBase.Account.Snapshot],
                    tokenMetadata: OpalBase.CashTokens.MetadataRepository.Snapshot? = nil) {
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
        return Snapshot(purpose: purpose,
                        coinType: coinType,
                        accounts: accountSnaps,
                        tokenMetadata: tokenMetadata)
    }
    
    public func applySnapshot(_ snapshot: Snapshot) async throws {
        guard snapshot.purpose == purpose,
              snapshot.coinType == coinType else {
            throw Error.snapshotDoesNotMatchWallet
        }
        
        var updatedAccounts: [UInt32: OpalBase.Account] = .init(minimumCapacity: snapshot.accounts.count)
        for accountSnap in snapshot.accounts {
            guard accountSnap.purpose == purpose,
                  accountSnap.coinType == coinType else {
                throw Error.snapshotDoesNotMatchWallet
            }
            let index = accountSnap.accountUnhardenedIndex

            if let account = accounts[index] {
                try await account.refresh(with: accountSnap)
                updatedAccounts[index] = account
            } else {
                let account = try await OpalBase.Account(
                    from: accountSnap,
                    rootExtendedPrivateKey: rootExtendedPrivateKey,
                    purpose: purpose,
                    coinType: coinType
                )
                updatedAccounts[index] = account
            }
        }
        self.accounts = updatedAccounts
        
        let tokenMetadata = snapshot.tokenMetadata ?? .init(byCategory: .init())
        await tokenMetadataStore.applySnapshot(tokenMetadata)
    }
}
