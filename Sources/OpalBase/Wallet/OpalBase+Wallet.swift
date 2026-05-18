// OpalBase+Wallet.swift

import Foundation
import OpalDiagnostics
import OpalCrypto

extension OpalBase {
    public actor Wallet: Identifiable {
        public let mnemonic: OpalBase.Key.Mnemonic
        public let passphrase: String
        let tokenMetadataStore: OpalBase.CashTokens.MetadataRepository
        let rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate
        
        let purpose: OpalBase.Key.DerivationPath.Purpose
        let coinType: OpalBase.Key.DerivationPath.CoinType
        
        public let id: Data
        
        var accounts: [UInt32: OpalBase.Account] = .init()
        
        public init(mnemonic: OpalBase.Key.Mnemonic,
                    passphrase: String = "",
                    purpose: OpalBase.Key.DerivationPath.Purpose = .bip44,
                    coinType: OpalBase.Key.DerivationPath.CoinType = .bitcoinCash) throws {
            let rootContext = try OpalDiagnostics.withTraceID {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.walletCreateStarted,
                    category: OpalDiagnostics.Category.wallet,
                    fields: [
                        OpalDiagnostics.Field.operation("wallet_create"),
                        OpalDiagnostics.Field.module()
                    ]
                )

                do {
                    let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
                        seed: OpalCrypto.Key.Seed(rawRepresentation: mnemonic.deriveSeed(passphrase: passphrase))
                    )
                    let id = [
                        try OpalCryptoAdapter.serializedExtendedKeyData(rootExtendedPrivateKey.serialize()),
                        purpose.hardenedIndex.data,
                        coinType.hardenedIndex.data,
                    ].generateID()
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.walletCreateSucceeded,
                        category: OpalDiagnostics.Category.wallet,
                        fields: [
                            OpalDiagnostics.Field.operation("wallet_create"),
                            OpalDiagnostics.Field.module()
                        ]
                    )
                    return (rootExtendedPrivateKey: rootExtendedPrivateKey, id: id)
                } catch {
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.walletCreateFailed,
                        category: OpalDiagnostics.Category.wallet,
                        fields: [
                            OpalDiagnostics.Field.operation("wallet_create"),
                            OpalDiagnostics.Field.module()
                        ] + OpalDiagnostics.Field.errorFields(for: error)
                    )
                    throw error
                }
            }

            self.mnemonic = mnemonic
            self.passphrase = passphrase
            self.tokenMetadataStore = OpalBase.CashTokens.MetadataRepository()
            self.rootExtendedPrivateKey = rootContext.rootExtendedPrivateKey
            self.purpose = purpose
            self.coinType = coinType
            self.id = rootContext.id
        }

        init(mnemonic: OpalCrypto.Key.Mnemonic,
             passphrase: String = "",
             purpose: OpalBase.Key.DerivationPath.Purpose = .bip44,
             coinType: OpalBase.Key.DerivationPath.CoinType = .bitcoinCash) throws {
            try self.init(mnemonic: .init(mnemonic),
                          passphrase: passphrase,
                          purpose: purpose,
                          coinType: coinType)
        }
        
        public init(
            mnemonic: OpalBase.Key.Mnemonic,
            passphrase: String = "",
            from snapshot: OpalBase.Wallet.Snapshot
        ) async throws {
            try self.init(
                mnemonic: mnemonic,
                passphrase: passphrase,
                purpose: snapshot.purpose,
                coinType: snapshot.coinType
            )
            try await applySnapshot(snapshot)
        }
    }
}

extension _OpalBase.Wallet: Equatable {
    public static func == (lhs: OpalBase.Wallet, rhs: OpalBase.Wallet) -> Bool {
        lhs.id == rhs.id
    }
}

extension _OpalBase.Wallet {
    public func addAccount(unhardenedIndex: UInt32) async throws {
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("wallet_account_create"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.accountIndex(unhardenedIndex)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.walletAccountCreateStarted,
                category: OpalDiagnostics.Category.wallet,
                fields: fields
            )

            do {
                guard accounts[unhardenedIndex] == nil else {
                    throw Error.accountAlreadyExists(index: unhardenedIndex)
                }

                let derivationPathAccount = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: unhardenedIndex)

                let account = try await OpalBase.Account(rootExtendedPrivateKey: rootExtendedPrivateKey,
                                                         purpose: purpose,
                                                         coinType: coinType,
                                                         account: derivationPathAccount)
                let index = await account.unhardenedIndex
                self.accounts[index] = account
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.walletAccountCreateSucceeded,
                    category: OpalDiagnostics.Category.wallet,
                    fields: fields
                )
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.walletAccountCreateFailed,
                    category: OpalDiagnostics.Category.wallet,
                    fields: fields + OpalDiagnostics.Field.errorFields(for: error)
                )
                throw error
            }
        }
    }
}

extension _OpalBase.Wallet {
    public func fetchTokenMetadata(
        for category: OpalBase.CashTokens.CategoryID
    ) async -> OpalBase.CashTokens.Metadata? {
        await tokenMetadataStore.fetchMetadata(for: category)
    }

    public func upsertTokenMetadata(
        _ items: [OpalBase.CashTokens.CategoryID: OpalBase.CashTokens.Metadata]
    ) async {
        await tokenMetadataStore.upsert(items)
    }

    public func makeTokenMetadataSnapshot() async -> OpalBase.CashTokens.MetadataRepository.Snapshot {
        await tokenMetadataStore.snapshot()
    }

    public func applyTokenMetadataSnapshot(
        _ snapshot: OpalBase.CashTokens.MetadataRepository.Snapshot
    ) async {
        await tokenMetadataStore.applySnapshot(snapshot)
    }
}

extension _OpalBase.Wallet {
    public var numberOfAccounts: Int { accounts.count }
    
    func updateAccounts(_ accounts: [OpalBase.Account]) async {
        var updatedAccounts: [UInt32: OpalBase.Account] = .init(minimumCapacity: accounts.count)
        for account in accounts {
            let index = await account.unhardenedIndex
            updatedAccounts[index] = account
        }
        self.accounts = updatedAccounts
    }
}

extension _OpalBase.Wallet {
    public var derivationPath: (purpose: OpalBase.Key.DerivationPath.Purpose, coinType: OpalBase.Key.DerivationPath.CoinType) {
        (purpose, coinType)
    }
    
    public func fetchAccount(at unhardenedIndex: UInt32) async throws -> OpalBase.Account {
        try OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("wallet_account_fetch"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.accountIndex(unhardenedIndex)
            ]
            do {
                guard let account = accounts[unhardenedIndex] else {
                    throw Error.cannotFetchAccount(index: unhardenedIndex)
                }

                OpalDiagnostics.record(
                    OpalDiagnostics.Event.walletAccountFetchSucceeded,
                    category: OpalDiagnostics.Category.wallet,
                    fields: fields
                )
                return account
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.walletAccountFetchFailed,
                    category: OpalDiagnostics.Category.wallet,
                    fields: fields + OpalDiagnostics.Field.errorFields(for: error)
                )
                throw error
            }
        }
    }
}

extension _OpalBase.Wallet {
    public func calculateCachedBalance() async throws -> OpalBase.Satoshi {
        var totalBalance: OpalBase.Satoshi = .init()
        for account in accounts.values {
            let balance = try await account.addressBook.calculateCachedTotalBalance()
            totalBalance = try totalBalance + balance
        }
        
        return totalBalance
    }
    
    public func calculateBalance(loader: @escaping @Sendable (OpalBase.Address) async throws -> OpalBase.Satoshi) async throws -> OpalBase.Satoshi {
        try await OpalDiagnostics.withTraceID {
            let fields = [
                OpalDiagnostics.Field.operation("wallet_balance_refresh"),
                OpalDiagnostics.Field.module(),
                OpalDiagnostics.Field.publicValue(OpalDiagnostics.Field.Name.accountCount, accounts.count)
            ]
            OpalDiagnostics.record(
                OpalDiagnostics.Event.walletBalanceRefreshStarted,
                category: OpalDiagnostics.Category.wallet,
                fields: fields
            )

            do {
                guard !accounts.isEmpty else {
                    let zero = try OpalBase.Satoshi(0)
                    OpalDiagnostics.record(
                        OpalDiagnostics.Event.walletBalanceRefreshSucceeded,
                        category: OpalDiagnostics.Category.wallet,
                        fields: fields
                    )
                    return zero
                }

                let total: OpalBase.Satoshi = try await withThrowingTaskGroup(of: OpalBase.Satoshi.self) { group in
                    for account in accounts.values {
                        group.addTask {
                            let refresh = try await account.refreshBalances(loader: loader)
                            return refresh.total
                        }
                    }

                    var aggregate: OpalBase.Satoshi = .init()
                    for try await partial in group {
                        aggregate = try aggregate + partial
                    }

                    return aggregate
                }

                OpalDiagnostics.record(
                    OpalDiagnostics.Event.walletBalanceRefreshSucceeded,
                    category: OpalDiagnostics.Category.wallet,
                    fields: fields
                )
                return total
            } catch {
                OpalDiagnostics.record(
                    OpalDiagnostics.Event.walletBalanceRefreshFailed,
                    category: OpalDiagnostics.Category.wallet,
                    fields: fields + OpalDiagnostics.Field.errorFields(for: error)
                )
                throw error
            }
        }
    }
}
