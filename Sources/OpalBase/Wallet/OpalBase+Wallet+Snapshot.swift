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

        let preparedAccounts = try await prepareSnapshotAccounts(snapshot.accounts)
        var updatedAccounts: [UInt32: OpalBase.Account] = .init(minimumCapacity: preparedAccounts.count)
        for preparedAccount in preparedAccounts {
            let index = preparedAccount.snapshot.accountUnhardenedIndex

            if let existingAccount = accounts[index] {
                do {
                    try await existingAccount.refresh(with: preparedAccount.snapshot)
                } catch {
                    throw Error.snapshotDoesNotMatchWallet
                }
                updatedAccounts[index] = existingAccount
            } else {
                updatedAccounts[index] = preparedAccount.validatedAccount
            }
        }
        self.accounts = updatedAccounts

        let tokenMetadata = snapshot.tokenMetadata ?? .init(byCategory: .init())
        await tokenMetadataStore.applySnapshot(tokenMetadata)
    }
}

private extension _OpalBase.Wallet {
    struct PreparedSnapshotAccount {
        let snapshot: OpalBase.Account.Snapshot
        let validatedAccount: OpalBase.Account
    }

    func prepareSnapshotAccounts(
        _ accountSnapshots: [OpalBase.Account.Snapshot]
    ) async throws -> [PreparedSnapshotAccount] {
        var seenIndices = Set<UInt32>()
        var preparedAccounts: [PreparedSnapshotAccount] = .init()
        preparedAccounts.reserveCapacity(accountSnapshots.count)

        for accountSnapshot in accountSnapshots {
            guard accountSnapshot.purpose == purpose,
                  accountSnapshot.coinType == coinType else {
                throw Error.snapshotDoesNotMatchWallet
            }

            let index = accountSnapshot.accountUnhardenedIndex
            guard seenIndices.insert(index).inserted else {
                throw Error.snapshotDoesNotMatchWallet
            }

            if let existingAccount = accounts[index] {
                let path = await existingAccount.derivationPath
                guard path.purpose == purpose,
                      path.coinType == coinType,
                      path.account.unhardenedIndex == index else {
                    throw Error.snapshotDoesNotMatchWallet
                }
            }

            let validatedAccount: OpalBase.Account
            do {
                validatedAccount = try await OpalBase.Account(
                    from: accountSnapshot,
                    rootExtendedPrivateKey: rootExtendedPrivateKey,
                    purpose: purpose,
                    coinType: coinType
                )
            } catch {
                throw Error.snapshotDoesNotMatchWallet
            }
            preparedAccounts.append(.init(snapshot: accountSnapshot, validatedAccount: validatedAccount))
        }

        return preparedAccounts
    }
}
