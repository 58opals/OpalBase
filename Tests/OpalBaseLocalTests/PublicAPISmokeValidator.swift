// PublicAPISmokeValidator.swift

import Foundation
import OpalDiagnostics
import Testing
import OpalBaseTestSupport
import OpalBase

@Suite("Public API smoke", .tags(.unit))
struct PublicAPISmokeValidator {
    @Test("mnemonic derives account extended public keys through OpalBase only")
    func mnemonicDerivesAccountExtendedPublicKeysThroughOpalBaseOnly() throws {
        let serialized = try makeSmokeMnemonic().makeSerializedAccountExtendedPublicKey(account: 0)

        #expect(serialized.hasPrefix("xpub"))
        #expect(serialized.isEmpty == false)
    }

    @Test("read-only accounts initialize from descriptors through OpalBase only")
    func verifyReadOnlyAccountsInitializeFromDescriptorsThroughOpalBaseOnly() async throws {
        let mnemonic = try makeSmokeMnemonic()
        let wallet = try OpalBase.Wallet(mnemonic: mnemonic)

        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let readOnlyAccount = try await OpalBase.Account(
            serializedAccountExtendedPublicKey: mnemonic.makeSerializedAccountExtendedPublicKey(account: 0),
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: 0,
            snapshot: await account.makeSnapshot()
        )

        #expect(await readOnlyAccount.unhardenedIndex == 0)
    }

    @Test("wallet, account, and network facades compose")
    func walletAccountAndNetworkFacadesCompose() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())

        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let configuration = OpalBase.Network.Configuration(
            serverURLs: [URL(string: "wss://fulcrum.example.com:50004")!],
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

        let nextReceivingAddress = try await account.reserveNextReceivingDerivedAddress()
        #expect(nextReceivingAddress.derivationPath.usage == .receiving)

        let listedReceivingAddresses = await account.listDerivedAddresses(
            for: OpalBase.Key.DerivationPath.Usage.receiving
        )
        #expect(listedReceivingAddresses.contains(nextReceivingAddress))

        await monitor.stop()
    }

    #if os(macOS)
    @Test("cash fusion readiness and status wrappers compose from OpalBase only")
    func cashFusionReadinessAndStatusWrappersComposeFromOpalBaseOnly() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())

        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let receivingAddress = try await account.selectNextDerivedAddress(
            for: OpalBase.Key.DerivationPath.Usage.receiving
        )
        let unspentOutput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: 120_000,
                address: receivingAddress.address
            ),
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x11, count: 32)),
            previousTransactionOutputIndex: 0
        )

        _ = try await account.refreshUTXOSet(
            using: makeSmokeAddressReader(
                unspentOutputsByAddress: [receivingAddress.address.string: [unspentOutput]]
            ),
            usage: .receiving
        )

        let readiness = try await account.evaluateCashFusionReadiness()

        #expect(readiness.pilotAvailability == .available)
        #expect(readiness.accountStatus == .ready)
        try #require(readiness.utxoEligibility.count == 1)
        let eligibility = try #require(readiness.utxoEligibility.first)
        #expect(eligibility.unspentOutput == unspentOutput)
        #expect(eligibility.status == .eligible)

        let sessionStatus = OpalBase.Account.CashFusionSessionStatus(
            isConnected: false,
            round: .init(
                identifier: "round-smoke",
                phase: .connecting,
                participantCount: nil,
                completionStatus: nil,
                isTerminal: false
            ),
            lastError: nil
        )

        #expect(sessionStatus.isConnected == false)
        #expect(sessionStatus.round?.identifier == "round-smoke")
        #expect(sessionStatus.round?.phase == .connecting)
        #expect(sessionStatus.lastError == nil)
        #expect(sessionStatus.lastErrorSummary == nil)
        #expect(sessionStatus.completedLocalOutputs.isEmpty)

        let completedSessionStatus = OpalBase.Account.CashFusionSessionStatus(
            isConnected: true,
            round: .init(
                identifier: "round-completed-smoke",
                phase: .completed,
                participantCount: 3,
                completionStatus: .success,
                isTerminal: true
            ),
            lastError: nil,
            completedLocalOutputs: [unspentOutput]
        )

        #expect(completedSessionStatus.completedLocalOutputs == [unspentOutput])

        let coordinatorStatus = OpalBase.Account.CashFusionSessionStatus.Coordinator(
            updateSequence: 4,
            latestMessageKind: "TierStatusUpdate",
            latestMessagePayloadByteCount: 24,
            queueStatus: .init(
                tierSatoshis: 100_000,
                playerCount: 3,
                minimumPlayerCount: 2,
                maximumPlayerCount: 8,
                timeRemainingSeconds: 17
            )
        )

        #expect(coordinatorStatus.queueStatus?.tierSatoshis == 100_000)
        #expect(coordinatorStatus.queueStatus?.playerCount == 3)
    }

    @Test("cash fusion coordinator configuration exposes TLS default and override")
    func cashFusionCoordinatorConfigurationExposesTLSDefaultAndOverride() {
        let defaultCoordinator = OpalBase.Account.CashFusionSession.Configuration.Coordinator(
            host: "fusion.example.com",
            port: 8787
        )
        let tlsCoordinator = OpalBase.Account.CashFusionSession.Configuration.Coordinator(
            host: "fusion.example.com",
            port: 8787,
            requiresTLS: true
        )

        #expect(defaultCoordinator.requiresTLS == false)
        #expect(tlsCoordinator.requiresTLS == true)
    }
    #endif

    @Test("transaction signature facade exposes owned enum")
    func transactionSignatureFacadeExposesOwnedEnum() {
        let signatureFormat: OpalBase.Transaction.SignatureFormat = .ecdsa(.der)

        #expect(signatureFormat == .ecdsa(.der))
        #expect(OpalBase.Transaction.SignatureFormat.schnorr == .schnorr)
    }

    @Test("Lockdown Mode boundary errors are Sendable")
    func lockdownModeBoundaryErrorsAreSendable() {
        requireSendable(OpalBase.WalletSecurityProfile.Error.self)
        requireSendable(OpalBase.WalletUnsignedTransactionEnvelope.Error.self)
    }

    @Test("signing key facade exposes compressed public key only")
    func signingKeyFacadeExposesCompressedPublicKeyOnly() throws {
        let signingKey = try OpalBase.Key.SigningKey(rawRepresentation: Data(repeating: 0x02, count: 32))
        let publicKey = signingKey.publicKey

        #expect(publicKey.compressedData.count == 33)
        #expect(publicKey.hash.count == 20)
        #expect(signingKey.description.contains("redacted"))
    }

    @Test("Cash Code facades compose through OpalBase only")
    func cashCodeFacadesComposeThroughOpalBaseOnly() throws {
        let scanSigningKey = try makeSmokeSigningKey(scalar: 7)
        let spendSigningKey = try makeSmokeSigningKey(scalar: 13)
        let senderInputSigningKey = try makeSmokeSigningKey(scalar: 37)
        let cashCode = OpalBase.ReusablePaymentAddress(
            cashCodeV1For: .mainnet,
            scanPublicKey: scanSigningKey.publicKey,
            spendPublicKey: spendSigningKey.publicKey
        )
        let encoded = try OpalBase.ReusablePaymentAddress.Codec()
            .encode(cashCode)
        let parsed = try OpalBase.ReusablePaymentAddress.Codec().parse(
            encoded,
            network: .mainnet
        )
        let payment = try parsed.derivePayment(
            from: senderInputSigningKey,
            spending: .init(
                transactionHash: .init(
                    naturalOrder: Data(repeating: 0x11, count: 32)
                ),
                outputIndex: 0
            )
        )
        let matcher = OpalBase.ReusablePaymentAddress.Matcher()
        do {
            _ = try matcher.matches(
                in: Data(),
                for: parsed,
                scanSigningKey: scanSigningKey,
                spendSigningKey: spendSigningKey
            )
            Issue.record("Expected an empty transaction payload to be rejected")
        } catch OpalBase.ReusablePaymentAddress.Error
            .invalidSerializedTransaction
        {
            // Expected: this call exists to compile the exact public matcher surface.
        }
        let confirmedReference =
            OpalBase.ReusablePaymentAddress.ConfirmedTransactionReference(
                transactionHash: .init(
                    naturalOrder: Data(repeating: 0x22, count: 32)
                ),
                blockHeight: 1
            )
        let mempoolReference =
            OpalBase.ReusablePaymentAddress.MempoolTransactionReference(
                transactionHash: .init(
                    naturalOrder: Data(repeating: 0x33, count: 32)
                ),
                fee: 500,
                hasUnconfirmedParent: false
            )
        let readerType:
            OpalBase.Network.Fulcrum.ReusablePaymentAddressReader.Type =
                OpalBase.Network.Fulcrum
                .ReusablePaymentAddressReader.self
        let compileReaderSurface:
            (
                OpalBase.Network.Fulcrum.Client,
                OpalBase.ReusablePaymentAddress.FilterPrefix
            ) async throws -> Void = { client, filterPrefix in
                let reader = OpalBase.Network.Fulcrum
                    .ReusablePaymentAddressReader(client: client)
                _ = try await reader.fetchConfirmedTransactionReferences(
                    matching: filterPrefix,
                    fromHeight: 0,
                    toHeight: nil
                )
                _ = try await reader.fetchMempoolTransactionReferences(
                    matching: filterPrefix
                )
            }

        #expect(parsed.profile == .cashCodeV1)
        #expect(parsed.filterPrefix.bitCount == 16)
        #expect(payment.childIndex == 0)
        #expect(payment.lockingScript.count == 25)
        #expect(confirmedReference.blockHeight == 1)
        #expect(mempoolReference.fee == 500)
        _ = matcher
        _ = readerType
        _ = compileReaderSurface
    }

    @Test("Cash Code restoration and sender facades compose through OpalBase only")
    func cashCodeLifecycleFacadesComposeThroughOpalBaseOnly() async throws {
        let scanSigningKey = try makeSmokeSigningKey(scalar: 7)
        let spendSigningKey = try makeSmokeSigningKey(scalar: 13)
        let address = OpalBase.ReusablePaymentAddress(
            cashCodeV1For: .mainnet,
            scanPublicKey: scanSigningKey.publicKey,
            spendPublicKey: spendSigningKey.publicKey
        )
        let candidates = OpalBase.Network.ReusablePaymentAddressReader(
            fetchConfirmedTransactionReferences: { _, _ in [] },
            fetchMempoolTransactionReferences: { _ in [] }
        )
        let transactions = OpalBase.Network.TransactionReader { _ in
            Data()
        }
        let storage = try OpalBase.Storage(
            valueClient: .makeInMemory(),
            security: .makePlaintextOnly(),
            secretPersistencePolicy: .acceptProviderOutput
        )
        let persistence = await storage
            .makeReusablePaymentAddressStatePersistence(
                identifier: Data("cash-code-smoke".utf8)
            )
        let restoration = try await OpalBase.CashCodeInteractor(
            transport: .init(
                candidates: candidates,
                transactions: transactions
            ),
            persistence: persistence
        ).openRestoration(
            for: address,
            keyOrigin: .init(
                scanKeyIdentifier: "smoke/scan",
                spendKeyIdentifier: "smoke/spend"
            ),
            restoreStartHeight: 100,
            scanSigningKey: scanSigningKey,
            spendSigningKey: spendSigningKey
        )
        let request = OpalBase.ReusablePaymentAddress.CashCodePaymentRequest(
            amount: try OpalBase.Satoshi(1_000)
        )
        let compileSenderSurface: @Sendable (
            OpalBase.WalletTransactionAuthoringInteractor,
            OpalBase.ReusablePaymentAddress.CashCodePaymentRequest,
            OpalBase.ReusablePaymentAddress
        ) async throws -> OpalBase.ReusablePaymentAddress.CashCodeSpendPlan = {
            interactor,
            request,
            address in
            try await interactor.prepareCashCodePayment(
                request,
                to: address,
                expectedNetwork: .mainnet
            )
        }

        #expect((await restoration.stateSnapshot).nextUnscannedHeight == 100)
        #expect(request.amount.uint64 == 1_000)
        _ = compileSenderSurface
    }

    @Test("claimable facade composes from OpalBase only")
    func claimableFacadeComposesFromOpalBaseOnly() throws {
        let refundPrivateKey = Data(repeating: 0, count: 31) + Data([0x02])
        let refundSigningKey = try OpalBase.Key.SigningKey(rawRepresentation: refundPrivateKey)
        let draft = try OpalBase.Claimable.Draft(
            network: .chipnet,
            refundSigningKey: refundSigningKey,
            expiryBlockHeight: 500
        )
        let fundingOutput = draft.makeFundingOutput(value: 20_000)
        let envelope = try OpalBase.Claimable.Envelope(
            contract: draft.contract,
            claimPrivateKey: draft.claimPrivateKey,
            fundingTransactionHash: .init(naturalOrder: Data(repeating: 0x44, count: 32)),
            fundingOutputIndex: 1,
            fundingValue: 20_000
        )
        let decodedEnvelope = try OpalBase.Claimable.Envelope.decode(
            from: envelope.encode(),
            on: .chipnet
        )
        let shareCode = try OpalBase.Claimable.ShareCode.encode(envelope: envelope)
        let decodedShareCodeEnvelope = try OpalBase.Claimable.ShareCode.decode(shareCode)
        let localStatus = decodedEnvelope.makeLocalStatus(currentBlockHeight: 499)
        let recoveryMaterial = try decodedEnvelope.makeClaimRecoveryMaterial()

        #expect(fundingOutput.lockingScript == draft.contract.fundingLockingScriptData)
        #expect(decodedEnvelope.contract == draft.contract)
        #expect(decodedShareCodeEnvelope == envelope)
        #expect(localStatus.allowsClaim)
        #expect(localStatus.allowsRefund == false)
        #expect(recoveryMaterial.spendPath == .claim)
        #expect(recoveryMaterial.fundingValueSatoshis == 20_000)
        #expect(recoveryMaterial.privateKeyWalletImportFormat.isEmpty == false)
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

    @Test("cash token transaction review facades compose from public API")
    func cashTokenTransactionReviewFacadesComposeFromPublicAPI() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())
        try await wallet.addAccount(unhardenedIndex: 0)
        let account = try await wallet.fetchAccount(at: 0)
        let receivingAddress = try await account.selectNextDerivedAddress(for: .receiving)
        let tokenAwareAddress = try receivingAddress.address.converted(to: .tokenAware)
        let category = try OpalBase.CashTokens.CategoryID(
            transactionOrderData: Data(repeating: 0x61, count: 32)
        )
        let tokenInputData = OpalBase.CashTokens.TokenData(category: category, amount: 100, nft: nil)
        let tokenInput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: 20_000,
                address: receivingAddress.address,
                tokenData: tokenInputData
            ),
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x62, count: 32)),
            previousTransactionOutputIndex: 0
        )
        let genesisInput = OpalBase.Transaction.Output.Unspent(
            output: .init(
                value: 120_000,
                address: receivingAddress.address
            ),
            previousTransactionHash: .init(naturalOrder: Data(repeating: 0x63, count: 32)),
            previousTransactionOutputIndex: 0
        )
        _ = try await account.refreshUTXOSet(
            using: makeSmokeAddressReader(
                unspentOutputsByAddress: [receivingAddress.address.string: [tokenInput, genesisInput]]
            ),
            usage: .receiving
        )

        let transfer = OpalBase.Account.TokenTransfer(recipients: [
            .init(
                address: tokenAwareAddress,
                amount: try OpalBase.Satoshi(1_000),
                tokenData: .init(category: category, amount: 5, nft: nil)
            )
        ])
        let tokenSpendPlan = try await account.prepareTokenSpend(transfer)
        let tokenSpendReview = try tokenSpendPlan.buildReview()
        let tokenRecipientOutput = try #require(tokenSpendReview.tokenRecipientOutputs.first)

        #expect(tokenAwareAddress.isTokenAware)
        #expect(tokenRecipientOutput.role == .recipient)
        #expect(tokenRecipientOutput.category == category)
        #expect(tokenRecipientOutput.fungibleAmount == 5)
        #expect(tokenSpendReview.rawTransactionByteCount == tokenSpendReview.rawTransactionData.count)
        try await tokenSpendPlan.cancelReservation()

        let genesis = try OpalBase.Account.TokenGenesis(recipients: [
            .init(address: tokenAwareAddress, fungibleAmount: 7)
        ])
        let tokenGenesisPlan = try await account.prepareTokenGenesis(
            genesis,
            preferredGenesisInput: genesisInput
        )
        let tokenGenesisReview = try tokenGenesisPlan.buildReview()
        let expectedTotalBCHNeeded = try tokenGenesisReview.lockedBCHOutputValue + tokenGenesisReview.fee
        let mintedOutput = try #require(tokenGenesisReview.mintedOutputs.first)

        #expect(tokenGenesisReview.category.transactionOrderData == genesisInput.previousTransactionHash.naturalOrder)
        #expect(mintedOutput.role == .minted)
        #expect(mintedOutput.fungibleAmount == 7)
        #expect(tokenGenesisReview.totalBCHNeeded == expectedTotalBCHNeeded)
        try await tokenGenesisPlan.cancelReservation()
    }

    @Test("storage persistence values accept facade test doubles")
    func storagePersistenceValuesAcceptFacadeTestDoubles() async throws {
        let wallet = try OpalBase.Wallet(mnemonic: makeSmokeMnemonic())
        try await wallet.addAccount(unhardenedIndex: 0)

        let snapshotState = SmokeSnapshotPersistenceState()
        let mnemonicState = SmokeStoredMnemonicPersistenceState()
        let session = OpalBase.Storage.PersistenceSession(
            snapshotPersistence: makeSmokeSnapshotPersistence(state: snapshotState),
            storedMnemonicPersistence: makeSmokeStoredMnemonicPersistence(state: mnemonicState)
        )

        let protectionMode = try await session.save(
            wallet: wallet
        )
        #expect(protectionMode == .plaintext)

        let restored = try await session.restore()
        #expect(restored.walletSnapshot?.accounts.count == 1)
        #expect(restored.mnemonic?.words == smokeMnemonicWords)
        #expect(restored.mnemonicProtectionMode == .plaintext)

        try await session.wipe()

        let wipedState = try await session.restore()
        #expect(wipedState.walletSnapshot == nil)
    }

    @Test("storage security facade exposes strict persistence policy types")
    func storageSecurityFacadeExposesStrictPersistencePolicyTypes() {
        let strictPolicy: OpalBase.Storage.Security.PersistencePolicy = .requireSecureEnclave
        let compatibilityPolicy: OpalBase.Storage.Security.PersistencePolicy = .legacyFallbackToPlaintext
        let configuration = OpalBase.Storage.Security.SecureEnclaveConfiguration(
            applicationTag: "example.secure-enclave"
        )

        #expect(strictPolicy != compatibilityPolicy)
        #expect(configuration.applicationTag == "example.secure-enclave")
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

    private let smokeMnemonicWords = [
        "abandon", "abandon", "abandon", "abandon", "abandon", "abandon",
        "abandon", "abandon", "abandon", "abandon", "abandon", "about"
    ]

    private func requireSendable<T: Sendable>(_ type: T.Type) {}

    private func makeSmokeMnemonic() throws -> OpalBase.Key.Mnemonic {
        try OpalBase.Key.Mnemonic(
            words: smokeMnemonicWords.map(OpalBase.Key.Mnemonic.Word.init),
            language: .english
        )
    }

    private func makeSmokeAddressReader(
        unspentOutputsByAddress: [String: [OpalBase.Transaction.Output.Unspent]] = [:]
    ) -> OpalBase.Network.AddressReader {
        OpalBase.Network.AddressReader(
            fetchBalance: { address, _ in
                .init(
                    confirmed: unspentOutputsByAddress[address, default: []].reduce(UInt64(0)) { $0 + $1.value },
                    unconfirmed: 0
                )
            },
            fetchUnspentOutputs: { address, _ in
                unspentOutputsByAddress[address, default: []]
            },
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

    private func makeSmokeSnapshotPersistence(state: SmokeSnapshotPersistenceState) -> OpalBase.Storage.SnapshotPersistence {
        OpalBase.Storage.SnapshotPersistence(
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

    private func makeSmokeStoredMnemonicPersistence(state: SmokeStoredMnemonicPersistenceState) -> OpalBase.Storage.StoredMnemonicPersistence {
        OpalBase.Storage.StoredMnemonicPersistence(
            secretPersistencePolicy: .legacyFallbackToPlaintext,
            saveMnemonic: { mnemonic, _, policy in
                await state.saveMnemonic(
                    mnemonic,
                    policy: policy
                )
            },
            loadMnemonicState: { _ in
                await state.loadMnemonicState()
            },
            deleteMnemonic: { generation in
                await state.deleteMnemonic(generation: generation)
            }
        )
    }

    private func smokeDiagnosticsConfiguration() -> OpalDiagnostics.Configuration {
        OpalDiagnostics.Configuration(
            minimumLevel: .debug,
            categoryFilter: .all,
            bufferPolicy: .enabled(capacity: 64)
        )
    }

    private func recordsContain(
        _ records: [OpalDiagnostics.Record],
        event: OpalDiagnostics.Event
    ) -> Bool {
        records.contains { $0.event == event }
    }
}

private extension PublicAPISmokeValidator {
    func makeSmokeSigningKey(
        scalar: UInt8
    ) throws -> OpalBase.Key.SigningKey {
        try OpalBase.Key.SigningKey(
            rawRepresentation: Data(repeating: 0, count: 31)
                + Data([scalar])
        )
    }
}
