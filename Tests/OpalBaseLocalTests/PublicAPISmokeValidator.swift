// PublicAPISmokeValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
import OpalBase

@Suite("Public API smoke", .tags(.unit))
struct PublicAPISmokeValidator {
    @Test("wallet, account, and network facades compose")
    func walletAccountAndNetworkFacadesCompose() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())

        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [URL(string: "wss://fulcrum.example.com:50002")!],
            network: .mainnet
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: makeSmokeAddressReader(),
            blockHeaderReader: makeSmokeBlockHeaderReader(),
            transactionClient: makeSmokeTransactionClient(),
            transactionReader: makeSmokeTransactionReader()
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            includeUnconfirmed: false,
            retryDelay: Duration.seconds(1)
        )

        #expect(await wallet.numberOfAccounts == 1)
        #expect(await account.unhardenedIndex == 0)
        #expect(configuration.serverURLs.count == 1)
        #expect(configuration.network == .mainnet)

        let cachedBalance = try await account.loadBalanceFromCache()
        #expect(cachedBalance.uint64 == 0)

        let cachedHistory = await account.loadTransactionHistory()
        #expect(cachedHistory.isEmpty)

        let nextReceivingEntry = try await account.selectNextEntry(
            for: OpalBase.Key.DerivationPath.Usage.receiving
        )
        #expect(nextReceivingEntry.derivationPath.usage == .receiving)

        await monitor.stop()
    }

    @Test("transaction signature facade exposes owned enum")
    func transactionSignatureFacadeExposesOwnedEnum() {
        let signatureFormat: OpalBase.Transaction.SignatureFormat = .ecdsa(.der)

        if case .ecdsa(.der) = signatureFormat {
            #expect(OpalBase.Transaction.SignatureFormat.schnorr == .schnorr)
        } else {
            Issue.record("Expected DER-backed ECDSA signature format.")
        }
    }

    @Test("cash token metadata facades interoperate")
    func cashTokenMetadataFacadesInterop() async throws {
        let client = OpalBase.CashTokens.BCMR.Client(
            authchainResolver: .init(
                transactionReader: makeSmokeTransactionReader(),
                addressReader: makeSmokeAddressReader(),
                maxDepth: 8
            ),
            registryFetcher: .init(maxBytes: 64 * 1_024)
        )
        let category = try OpalBase.CashTokens.CategoryID(
            hexFromRPC: BitcoinCashMetadataRegistryTestData.categoryHexadecimal
        )
        let importedMetadata = try client.addEmbeddedRegistry(
            data: BitcoinCashMetadataRegistryTestData.registryData
        )

        #expect(importedMetadata.keys.contains(category))

        let repository = OpalBase.CashTokens.MetadataRepository()
        await repository.upsert(importedMetadata)

        let fetchedImportedMetadata = await repository.fetchMetadata(for: category)
        #expect(fetchedImportedMetadata?.symbol == "EXAMPLE")

        let manualMetadata = OpalBase.CashTokens.Metadata(
            category: category,
            name: "Manual Token",
            symbol: "MANUAL",
            decimals: 0,
            iconURL: nil,
            lastUpdated: Date(timeIntervalSince1970: 0),
            source: .embedded
        )
        await repository.upsert([category: manualMetadata])

        let fetchedManualMetadata = await repository.fetchMetadata(for: category)
        #expect(fetchedManualMetadata?.name == "Manual Token")

        let snapshot = await repository.snapshot()
        let restoredRepository = OpalBase.CashTokens.MetadataRepository()
        await restoredRepository.applySnapshot(snapshot)

        let restoredMetadata = await restoredRepository.fetchMetadata(for: category)
        #expect(restoredMetadata?.symbol == "MANUAL")

        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())
        await wallet.upsertTokenMetadata([category: manualMetadata])

        let walletMetadata = await wallet.fetchTokenMetadata(for: category)
        #expect(walletMetadata?.name == "Manual Token")
        #expect((await wallet.makeTokenMetadataSnapshot()).byCategory.keys.contains(category.hexForDisplay))
    }

    @Test("storage concrete stores accept facade test doubles")
    func storageConcreteStoresAcceptFacadeTestDoubles() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())
        try await wallet.addAccount(unhardenedIndex: 0)

        let snapshotState = SmokeSnapshotStoreState()
        let mnemonicState = SmokeStoredMnemonicStoreState()
        let session = OpalBase.Storage.PersistenceSession(
            snapshotStore: makeSmokeSnapshotStore(state: snapshotState),
            storedMnemonicStore: makeSmokeStoredMnemonicStore(state: mnemonicState)
        )

        let protectionMode = try await session.save(wallet: wallet)
        #expect(protectionMode == .plaintext)

        let restored = try await session.restore()
        #expect(restored.walletSnapshot?.accounts.count == 1)
        #expect(restored.mnemonic?.words == smokeMnemonicWords)
        #expect(restored.mnemonicProtectionMode == .plaintext)

        try await session.wipe()

        let wipedState = try await session.restore()
        #expect(wipedState.walletSnapshot == nil)
    }

    @Test("encoding and block target facades expose proof-of-work target")
    func encodingAndBlockTargetFacadesExposeComparableProofOfWorkTarget() throws {
        let header = OpalBase.Block.Header(
            version: 1,
            previousBlockHash: Data(repeating: 0x00, count: 32),
            merkleRoot: try OpalBase.Encoding.data(
                fromHexadecimal: "3ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a"
            ),
            time: 1_231_006_505,
            bits: 0x1d00ffff,
            nonce: 2_083_236_893
        )
        let expectedTarget = OpalBase.Block.Target(
            data: try OpalBase.Encoding.data(
                fromHexadecimal: "00000000ffff0000000000000000000000000000000000000000000000000000"
            )
        )
        let easierTarget = OpalBase.Block.Header.calculateTarget(for: 0x1f00ffff)
        let calculatedTarget = OpalBase.Block.Header.calculateTarget(for: header.bits)

        #expect(calculatedTarget == expectedTarget)
        #expect(calculatedTarget < easierTarget)
        #expect(header.isProofOfWorkSatisfied)
    }
}

private let smokeMnemonicWords = [
    "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
    "abandon", "abandon", "abandon", "abandon", "abandon", "about"
]

private func makeSmokeMnemonic() throws -> OpalBase.Key.Mnemonic {
    try OpalBase.Key.Mnemonic(
        words: smokeMnemonicWords.map(OpalBase.Key.Mnemonic.Word.init),
        language: .english
    )
}

private func makeSmokeAddressReader() -> OpalBase.Network.AddressReader {
    OpalBase.Network.AddressReader(
        fetchBalance: { _, _ in .init(confirmed: 0, unconfirmed: 0) },
        fetchUnspentOutputs: { _, _ in [] },
        fetchHistory: { _, _ in [] },
        fetchFirstUse: { _ in nil },
        fetchMempoolTransactions: { _ in [] },
        fetchScriptHash: { _ in "00" },
        subscribeToAddress: { _ in
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    )
}

private func makeSmokeTransactionReader() -> OpalBase.Network.TransactionReader {
    OpalBase.Network.TransactionReader(fetchRawTransaction: { _ in Data() })
}

private func makeSmokeTransactionClient() -> OpalBase.Network.TransactionClient {
    OpalBase.Network.TransactionClient(
        broadcastTransaction: { _ in String(repeating: "0", count: 64) },
        fetchConfirmations: { _ in nil },
        fetchConfirmationStatus: { transactionHash in
            .init(
                transactionHash: transactionHash,
                transactionHeight: nil,
                tipHeight: 0,
                confirmations: nil
            )
        }
    )
}

private func makeSmokeBlockHeaderReader() -> OpalBase.Network.BlockHeaderReader {
    OpalBase.Network.BlockHeaderReader(
        fetchTip: { .init(height: 0, headerHexadecimal: "") },
        subscribeToTip: {
            AsyncThrowingStream { continuation in
                continuation.finish()
            }
        }
    )
}

private actor SmokeSnapshotStoreState {
    private var walletSnapshots: [String: OpalBase.Wallet.Snapshot] = [:]
    private var committedGeneration: String?

    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot, generation: String) {
        walletSnapshots[generation] = snapshot
    }

    func loadWalletSnapshot(generation: String) -> OpalBase.Wallet.Snapshot? {
        walletSnapshots[generation]
    }

    func deleteWalletSnapshot(generation: String) {
        walletSnapshots.removeValue(forKey: generation)
    }

    func saveCommittedGeneration(_ generation: String) {
        committedGeneration = generation
    }

    func loadCommittedGeneration() -> String? {
        committedGeneration
    }

    func deleteCommittedGeneration() {
        committedGeneration = nil
    }

    func wipeAll() {
        walletSnapshots.removeAll()
        committedGeneration = nil
    }
}

private actor SmokeStoredMnemonicStoreState {
    private var state: (
        mnemonic: OpalBase.Storage.StoredMnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )?

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.StoredMnemonic,
        fallbackToPlaintext: Bool
    ) -> OpalBase.Storage.Security.ProtectionMode {
        let mode: OpalBase.Storage.Security.ProtectionMode = fallbackToPlaintext ? .plaintext : .software
        state = (mnemonic, mode)
        return mode
    }

    func loadMnemonicState() -> (
        mnemonic: OpalBase.Storage.StoredMnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )? {
        state
    }

    func deleteMnemonic(generation _: String) {
        state = nil
    }
}

private func makeSmokeSnapshotStore(state: SmokeSnapshotStoreState) -> OpalBase.Storage.SnapshotStore {
    OpalBase.Storage.SnapshotStore(
        saveWalletSnapshot: { snapshot, generation in
            await state.saveWalletSnapshot(snapshot, generation: generation)
        },
        loadWalletSnapshot: { generation in
            await state.loadWalletSnapshot(generation: generation)
        },
        deleteWalletSnapshot: { generation in
            await state.deleteWalletSnapshot(generation: generation)
        },
        saveCommittedGeneration: { generation in
            await state.saveCommittedGeneration(generation)
        },
        loadCommittedGeneration: {
            await state.loadCommittedGeneration()
        },
        deleteCommittedGeneration: {
            await state.deleteCommittedGeneration()
        }
    )
}

private func makeSmokeStoredMnemonicStore(state: SmokeStoredMnemonicStoreState) -> OpalBase.Storage.StoredMnemonicStore {
    OpalBase.Storage.StoredMnemonicStore(
        saveMnemonic: { mnemonic, _, fallbackToPlaintext in
            await state.saveMnemonic(mnemonic, fallbackToPlaintext: fallbackToPlaintext)
        },
        loadMnemonicState: { _ in
            await state.loadMnemonicState()
        },
        deleteMnemonic: { generation in
            await state.deleteMnemonic(generation: generation)
        }
    )
}
