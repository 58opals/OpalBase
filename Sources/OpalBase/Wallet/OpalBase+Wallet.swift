// OpalBase+Wallet.swift

import Foundation
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
            let rootContext = try OpalBase.Diagnostics.withTraceID {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.walletCreateStarted,
                    category: OpalBase.Diagnostics.Categories.wallet,
                    fields: [
                        OpalBaseDiagnostics.operationField("wallet_create"),
                        OpalBaseDiagnostics.moduleField()
                    ]
                )

                do {
                    let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
                        seed: OpalCrypto.Key.Seed(rawRepresentation: mnemonic.deriveSeed(passphrase: passphrase))
                    )
                    let id = [
                        OpalCryptoAdapter.serializedExtendedKeyData(rootExtendedPrivateKey.serialize()),
                        purpose.hardenedIndex.data,
                        coinType.hardenedIndex.data,
                    ].generateID()
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.walletCreateSucceeded,
                        category: OpalBase.Diagnostics.Categories.wallet,
                        fields: [
                            OpalBaseDiagnostics.operationField("wallet_create"),
                            OpalBaseDiagnostics.moduleField()
                        ]
                    )
                    return (rootExtendedPrivateKey: rootExtendedPrivateKey, id: id)
                } catch {
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.walletCreateFailed,
                        category: OpalBase.Diagnostics.Categories.wallet,
                        fields: [
                            OpalBaseDiagnostics.operationField("wallet_create"),
                            OpalBaseDiagnostics.moduleField()
                        ] + OpalBaseDiagnostics.errorFields(for: error)
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
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("wallet_account_create"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.accountIndexField(unhardenedIndex)
            ]
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.walletAccountCreateStarted,
                category: OpalBase.Diagnostics.Categories.wallet,
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
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.walletAccountCreateSucceeded,
                    category: OpalBase.Diagnostics.Categories.wallet,
                    fields: fields
                )
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.walletAccountCreateFailed,
                    category: OpalBase.Diagnostics.Categories.wallet,
                    fields: fields + OpalBaseDiagnostics.errorFields(for: error)
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
        try OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("wallet_account_fetch"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.accountIndexField(unhardenedIndex)
            ]
            do {
                guard let account = accounts[unhardenedIndex] else {
                    throw Error.cannotFetchAccount(index: unhardenedIndex)
                }

                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.walletAccountFetchSucceeded,
                    category: OpalBase.Diagnostics.Categories.wallet,
                    fields: fields
                )
                return account
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.walletAccountFetchFailed,
                    category: OpalBase.Diagnostics.Categories.wallet,
                    fields: fields + OpalBaseDiagnostics.errorFields(for: error)
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
        try await OpalBase.Diagnostics.withTraceID {
            let fields = [
                OpalBaseDiagnostics.operationField("wallet_balance_refresh"),
                OpalBaseDiagnostics.moduleField(),
                OpalBaseDiagnostics.publicField(OpalBase.Diagnostics.Fields.accountCount, accounts.count)
            ]
            OpalBaseDiagnostics.record(
                OpalBase.Diagnostics.Events.walletBalanceRefreshStarted,
                category: OpalBase.Diagnostics.Categories.wallet,
                fields: fields
            )

            do {
                guard !accounts.isEmpty else {
                    let zero = try OpalBase.Satoshi(0)
                    OpalBaseDiagnostics.record(
                        OpalBase.Diagnostics.Events.walletBalanceRefreshSucceeded,
                        category: OpalBase.Diagnostics.Categories.wallet,
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

                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.walletBalanceRefreshSucceeded,
                    category: OpalBase.Diagnostics.Categories.wallet,
                    fields: fields
                )
                return total
            } catch {
                OpalBaseDiagnostics.record(
                    OpalBase.Diagnostics.Events.walletBalanceRefreshFailed,
                    category: OpalBase.Diagnostics.Categories.wallet,
                    fields: fields + OpalBaseDiagnostics.errorFields(for: error)
                )
                throw error
            }
        }
    }
}
