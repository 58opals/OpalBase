// PublicAPISmokeValidator.swift

import Foundation
import OpalCrypto
import Testing
import OpalBaseTestSupport
import OpalBase

@Suite("Public API smoke", .tags(.unit))
struct PublicAPISmokeValidator {
    @Test("wallet, account, and network facades compose in public API")
    func walletAccountAndNetworkFacadesCompose() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())

        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [URL(string: "wss://fulcrum.example.com:50002")!],
            network: .mainnet
        )
        let fulcrum = OpalBase.Wallet.Fulcrum(
            addressReader: SmokeAddressClient(),
            transactionHandler: SmokeTransactionClient()
        )
        let monitor = await fulcrum.makeMonitor(
            for: account,
            blockHeaderReader: SmokeBlockHeaderClient(),
            includeUnconfirmed: false,
            retryDelay: .seconds(1)
        )

        #expect(await wallet.numberOfAccounts == 1)
        #expect(await account.unhardenedIndex == 0)
        #expect(configuration.serverURLs.count == 1)
        #expect(configuration.network == .mainnet)

        let cachedBalance = try await account.loadBalanceFromCache()
        #expect(cachedBalance.uint64 == 0)

        let cachedHistory = await account.loadTransactionHistory()
        #expect(cachedHistory.isEmpty)

        let nextReceivingEntry = try await account.selectNextEntry(for: .receiving)
        #expect(nextReceivingEntry.derivationPath.usage == .receiving)

        await monitor.stop()
    }

    @Test("OpalCrypto facade types sign and verify")
    func opalCryptoFacadeRoundTripsSignatures() throws {
        let privateKey32 = Data(repeating: 0x01, count: 32)
        let digest32 = Data(repeating: 0x02, count: 32)
        let publicKey = try OpalCrypto.Signature.derivePublicKey(fromPrivateKey: privateKey32)

        let derSignature = try OpalCrypto.Signature.sign(
            message: digest32,
            privateKey: privateKey32,
            format: .ecdsa(.der)
        )
        let rawSignature = try OpalCrypto.Secp256k1.decodeDER(derSignature)
        let roundTrippedSignature = try OpalCrypto.Secp256k1.encodeDER(rawSignature)

        #expect(roundTrippedSignature == derSignature)
        #expect(
            try OpalCrypto.Signature.verify(
                signature: derSignature,
                message: digest32,
                publicKey: publicKey
                ,
                format: .ecdsa(.der)
            )
        )

        let schnorrSignature = try OpalCrypto.Signature.sign(
            message: digest32,
            privateKey: privateKey32,
            format: .schnorr,
            nonce: .bip340Deterministic
        )

        #expect(
            try OpalCrypto.Signature.verify(
                signature: schnorrSignature,
                message: digest32,
                publicKey: publicKey,
                format: .schnorr
            )
        )

        let signatureFormat: OpalCrypto.Signature.Format = .ecdsa(.der)
        let noncePolicy = OpalCrypto.Signature.NoncePolicy.rfc6979

        if case .ecdsa(.der) = signatureFormat {
            #expect(noncePolicy == .rfc6979)
        } else {
            Issue.record("Expected DER-backed ECDSA signature format.")
        }
    }

    @Test("cash token metadata facades interoperate")
    func cashTokenMetadataFacadesInterop() async throws {
        let client = OpalBase.CashTokens.BCMR.Client(
            authchainResolver: .init(
                transactionReader: SmokeTransactionReader(),
                addressReader: SmokeAddressClient(),
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

        let fetchedImportedMetadata = try #require(
            await repository.fetchMetadata(for: category)
        )
        #expect(fetchedImportedMetadata.symbol == "EXAMPLE")

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

        let fetchedManualMetadata = try #require(
            await repository.fetchMetadata(for: category)
        )
        #expect(fetchedManualMetadata.name == "Manual Token")

        let snapshot = await repository.snapshot()
        let restoredRepository = OpalBase.CashTokens.MetadataRepository()
        await restoredRepository.applySnapshot(snapshot)

        let restoredMetadata = try #require(
            await restoredRepository.fetchMetadata(for: category)
        )
        #expect(restoredMetadata.symbol == "MANUAL")

        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())
        await wallet.upsertTokenMetadata([category: manualMetadata])

        let walletMetadata = try #require(await wallet.fetchTokenMetadata(for: category))
        #expect(walletMetadata.name == "Manual Token")
        #expect((await wallet.makeTokenMetadataSnapshot()).byCategory.keys.contains(category.hexForDisplay))
    }

    @Test("storage ports accept public protocol test doubles")
    func storagePortsAcceptProtocolTestDoubles() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())
        try await wallet.addAccount(unhardenedIndex: 0)

        let snapshotStore = SmokeSnapshotClient()
        let secretStore = SmokeMnemonicSecretClient()
        let ports = OpalBase.Storage.Ports(
            snapshotPersistence: snapshotStore,
            secretAccess: secretStore
        )
        let session = OpalBase.Storage.PersistenceSession(ports: ports)

        let protectionMode = try await session.save(wallet: wallet)
        #expect(protectionMode == .plaintext)

        let account = try await wallet.fetchAccount(at: 0)
        let accountIdentifier = await account.id
        let restored = try await session.restore(accountIdentifiers: [accountIdentifier])
        let restoredWalletSnapshot = try #require(restored.walletSnapshot)
        let restoredAccountSnapshot = try #require(restored.accountSnapshots[accountIdentifier])
        let restoredMnemonic = try #require(restored.mnemonic)

        #expect(restoredWalletSnapshot.accounts.count == 1)
        #expect(restoredAccountSnapshot.accountUnhardenedIndex == 0)
        #expect(restoredMnemonic.words == smokeMnemonicWords)
        #expect(restored.mnemonicProtectionMode == .plaintext)

        try await session.wipe()

        let wipedState = try await session.restore(accountIdentifiers: [accountIdentifier])
        switch wipedState.walletSnapshot {
        case nil:
            break
        case .some:
            Issue.record("Expected wallet snapshot storage to be wiped.")
        }
        #expect(wipedState.accountSnapshots.isEmpty)
        #expect(wipedState.addressBookSnapshots.isEmpty)
    }

    @Test("block target facade exposes comparable proof-of-work target")
    func blockTargetFacadeExposesComparableProofOfWorkTarget() throws {
        let header = OpalBase.Block.Header(
            version: 1,
            previousBlockHash: Data(repeating: 0x00, count: 32),
            merkleRoot: try Data(
                hexadecimalString: "3ba3edfd7a7b12b27ac72c3e67768f617fc81bc3888a51323a9fb8aa4b1e5e4a"
            ),
            time: 1_231_006_505,
            bits: 0x1d00ffff,
            nonce: 2_083_236_893
        )
        let expectedTarget = OpalBase.Block.Target(
            data: try Data(
                hexadecimalString: "00000000ffff0000000000000000000000000000000000000000000000000000"
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

private func makeSmokeMnemonic() throws -> OpalCrypto.Key.Mnemonic {
    try OpalCrypto.Key.Mnemonic(words: smokeMnemonicWords.map(OpalCrypto.Key.Mnemonic.Word.init))
}

private actor SmokeAddressClient: OpalBase.Network.AddressReadable {
    func fetchBalance(
        for _: String,
        tokenFilter _: OpalBase.Network.TokenFilter
    ) async throws -> OpalBase.Network.AddressBalance {
        .init(confirmed: 0, unconfirmed: 0)
    }

    func fetchUnspentOutputs(
        for _: String,
        tokenFilter _: OpalBase.Network.TokenFilter
    ) async throws -> [OpalBase.Transaction.Output.Unspent] {
        []
    }

    func fetchHistory(
        for _: String,
        includeUnconfirmed _: Bool
    ) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        []
    }

    func fetchFirstUse(for _: String) async throws -> OpalBase.Network.AddressFirstUse? {
        nil
    }

    func fetchMempoolTransactions(for _: String) async throws -> [OpalBase.Network.TransactionHistoryEntry] {
        []
    }

    func fetchScriptHash(for _: String) async throws -> String {
        "00"
    }

    func subscribeToAddress(
        _: String
    ) async throws -> AsyncThrowingStream<OpalBase.Network.AddressSubscriptionUpdate, any Swift.Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private actor SmokeTransactionReader: OpalBase.Network.TransactionReadableClient {
    func fetchRawTransaction(for _: OpalBase.Transaction.Hash) async throws -> Data {
        Data()
    }
}

private actor SmokeTransactionClient: OpalBase.Network.TransactionConfirmationClient {
    func fetchConfirmations(forTransactionIdentifier _: String) async throws -> UInt? {
        nil
    }

    func fetchConfirmationStatus(
        for transactionHash: OpalBase.Transaction.Hash
    ) async throws -> OpalBase.Network.TransactionConfirmationStatus {
        .init(
            transactionHash: transactionHash,
            transactionHeight: nil,
            tipHeight: 0,
            confirmations: nil
        )
    }
}

private actor SmokeBlockHeaderClient: OpalBase.Network.BlockHeaderReadable {
    func fetchTip() async throws -> OpalBase.Network.BlockHeaderSnapshot {
        .init(height: 0, headerHexadecimal: "")
    }

    func subscribeToTip() async throws -> AsyncThrowingStream<OpalBase.Network.BlockHeaderSnapshot, any Swift.Error> {
        AsyncThrowingStream { continuation in
            continuation.finish()
        }
    }
}

private actor SmokeSnapshotClient: OpalBase.Storage.SnapshotClient {
    private var walletSnapshot: OpalBase.Wallet.Snapshot?
    private var accountSnapshots: [Data: OpalBase.Account.Snapshot] = [:]
    private var addressBookSnapshots: [Data: OpalBase.Address.Book.Snapshot] = [:]

    func saveWalletSnapshot(_ snapshot: OpalBase.Wallet.Snapshot) async throws {
        walletSnapshot = snapshot
    }

    func loadWalletSnapshot() async throws -> OpalBase.Wallet.Snapshot? {
        walletSnapshot
    }

    func saveAccountSnapshot(
        _ snapshot: OpalBase.Account.Snapshot,
        accountIdentifier: Data
    ) async throws {
        accountSnapshots[accountIdentifier] = snapshot
    }

    func loadAccountSnapshot(accountIdentifier: Data) async throws -> OpalBase.Account.Snapshot? {
        accountSnapshots[accountIdentifier]
    }

    func saveAddressBookSnapshot(
        _ snapshot: OpalBase.Address.Book.Snapshot,
        accountIdentifier: Data
    ) async throws {
        addressBookSnapshots[accountIdentifier] = snapshot
    }

    func loadAddressBookSnapshot(accountIdentifier: Data) async throws -> OpalBase.Address.Book.Snapshot? {
        addressBookSnapshots[accountIdentifier]
    }

    func wipeAll() async throws {
        walletSnapshot = nil
        accountSnapshots.removeAll()
        addressBookSnapshots.removeAll()
    }
}

private actor SmokeMnemonicSecretClient: OpalBase.Storage.MnemonicSecretClient {
    private var state: (
        mnemonic: OpalBase.Storage.Mnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )?

    func saveMnemonic(
        _ mnemonic: OpalBase.Storage.Mnemonic,
        fallbackToPlaintext: Bool
    ) async throws -> OpalBase.Storage.Security.ProtectionMode {
        let mode: OpalBase.Storage.Security.ProtectionMode = fallbackToPlaintext ? .plaintext : .software
        state = (mnemonic, mode)
        return mode
    }

    func loadMnemonicState() async throws -> (
        mnemonic: OpalBase.Storage.Mnemonic,
        protectionMode: OpalBase.Storage.Security.ProtectionMode
    )? {
        state
    }
}
