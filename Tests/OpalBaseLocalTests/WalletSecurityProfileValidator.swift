// WalletSecurityProfileValidator.swift

import Foundation
import Testing
@testable import OpalBase

@Suite("Wallet security profile", .tags(.unit, .wallet))
struct WalletSecurityProfileValidator {
    @Test("offline savings signer profile fails closed and disables broadcast")
    func offlineSavingsSignerProfileFailsClosedAndDisablesBroadcast() {
        let profile = OpalBase.WalletSecurityProfile.offlineSavingsSigner

        #expect(profile.secretPersistencePolicy == .requireSecureEnclave)
        #expect(profile.networkAccess == .offline)
        #expect(profile.signingAccess == .externalReviewRequired)
        #expect(profile.requiresSecureEnclaveSecretPersistence)
        #expect(profile.requiresExternalSigningReview)
        #expect(profile.requiresOfflineNetworkAccess)
        #expect(profile.allowsBroadcasting == false)
    }

    @Test("offline savings signer profile rejects broadcast interactor construction")
    func offlineSavingsSignerProfileRejectsBroadcastInteractorConstruction() {
        let transactionClient = OpalBase.Network.TransactionClient(
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

        #expect(
            throws: OpalBase.WalletSecurityProfile.Error.broadcastUnavailable(networkAccess: .offline)
        ) {
            _ = try OpalBase.WalletBroadcastInteractor(
                profile: .offlineSavingsSigner,
                transactionClient: transactionClient
            )
        }
    }

    @Test("secret lane saves through wallet security profile")
    func secretLaneSavesThroughWalletSecurityProfile() async throws {
        let storage = try OpalBase.Storage(
            valueClient: .makeInMemory(),
            security: Self.makeSecureEnclaveModeSecurity()
        )
        let secrets = await OpalBase.WalletSecretAccessInteractor(storage: storage)
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "offline-savings")

        let protectionMode = try await secrets.saveWalletSecretsAndSnapshot(
            from: wallet,
            profile: .offlineSavingsSigner
        )

        #expect(protectionMode == .secureEnclave)
    }

    @Test("storage-backed secret lane wipe resets protected material")
    func storageBackedSecretLaneWipeResetsProtectedMaterial() async throws {
        let storage = try OpalBase.Storage(
            valueClient: .makeInMemory(),
            security: Self.makeSecureEnclaveModeSecurity(
                protectedMaterialReset: {
                    throw SecretLaneProtectedMaterialResetFailure.resetInvoked
                }
            )
        )
        let secrets = await OpalBase.WalletSecretAccessInteractor(storage: storage)

        await #expect(throws: SecretLaneProtectedMaterialResetFailure.resetInvoked) {
            try await secrets.wipeWalletSecretsAndSnapshots()
        }
    }

    @Test(
        "secret lane wipe resets storage protected material",
        arguments: SecretLaneInteractorConstructionCase.allCases
    )
    func secretLaneWipeResetsStorageProtectedMaterial(
        _ constructionCase: SecretLaneInteractorConstructionCase
    ) async throws {
        let resetProbe = ProtectedMaterialResetProbe()
        let storage = try OpalBase.Storage(
            valueClient: .makeInMemory(),
            security: Self.makeSecureEnclaveModeSecurity(
                protectedMaterialReset: {
                    resetProbe.recordReset()
                }
            )
        )
        let secrets = await constructionCase.makeSecretAccessInteractor(storage: storage)
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "wipe-reset-\(constructionCase.slug)")

        _ = try await secrets.saveWalletSecretsAndSnapshot(from: wallet, policy: .acceptProviderOutput)
        try await secrets.wipeWalletSecretsAndSnapshots()

        #expect(resetProbe.wasReset)
    }

    @Test("storage-backed secret lane wipe resets protected material after persisted delete failure")
    func storageBackedSecretLaneWipeResetsProtectedMaterialAfterPersistedDeleteFailure() async throws {
        let valueStore = FailingCommittedGenerationDeleteValueStorage()
        let resetProbe = ProtectedMaterialResetProbe()
        let storage = try OpalBase.Storage(
            valueClient: valueStore.makeValueClient(),
            security: Self.makeSecureEnclaveModeSecurity(
                protectedMaterialReset: {
                    resetProbe.recordReset()
                }
            )
        )
        let secrets = await OpalBase.WalletSecretAccessInteractor(storage: storage)
        let wallet = try await AccountTestFixtures.makeWallet(passphrase: "wipe-reset-after-delete-failure")

        _ = try await secrets.saveWalletSecretsAndSnapshot(from: wallet, policy: .acceptProviderOutput)

        try await Self.requireStoragePersistenceFailure(
            underlying: SecretLaneWipeFailure.committedGenerationDeleteFailed
        ) {
            try await secrets.wipeWalletSecretsAndSnapshots()
        }
        #expect(resetProbe.wasReset)
    }

    @Test("unsigned transaction envelope records external signing material")
    func unsignedTransactionEnvelopeRecordsExternalSigningMaterial() {
        let spentOutput = OpalBase.Transaction.Output(
            value: 10_000,
            lockingScript: Data([0x51])
        )
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x51),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data(),
                    sequence: 0xFFFFFFFF
                )
            ],
            outputs: [
                .init(value: 9_000, lockingScript: Data([0x51]))
            ],
            lockTime: 0
        )

        let envelope = OpalBase.WalletUnsignedTransactionEnvelope(
            unsignedTransaction: unsignedTransaction,
            spentOutputs: [spentOutput]
        )

        #expect(envelope.signatureFormat == .schnorr)
        #expect(envelope.hasMatchingInputAndSpentOutputCounts)
    }

    @Test(
        "external review rejects unsupported raw ECDSA signature format",
        arguments: UnsupportedSignatureFormatBoundaryCase.allCases
    )
    func externalReviewRejectsUnsupportedRawECDSASignatureFormat(
        _ boundaryCase: UnsupportedSignatureFormatBoundaryCase
    ) throws {
        try boundaryCase.validateUnsupportedRawECDSARejection()
    }

    @Test("unsigned transaction envelope validates signed transaction structure")
    func unsignedTransactionEnvelopeValidatesSignedTransactionStructure() throws {
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x52),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data([0x00]),
                    sequence: 0xFFFFFFFF
                )
            ],
            outputs: [
                .init(value: 9_000, lockingScript: Data([0x51]))
            ],
            lockTime: 0
        )
        let envelope = OpalBase.WalletUnsignedTransactionEnvelope(
            unsignedTransaction: unsignedTransaction,
            spentOutputs: [
                .init(value: 10_000, lockingScript: Data([0x51]))
            ]
        )
        let signedTransaction = Self.makeSignedTransaction(matching: unsignedTransaction) { _, _ in
            Data([0x41])
        }

        try envelope.validateSignedTransactionStructure(signedTransaction)
    }

    @Test(
        "unsigned transaction envelope rejects missing and unchanged signed unlocking scripts per input",
        arguments: SignedUnlockingScriptFailureCase.allCases
    )
    func unsignedTransactionEnvelopeRejectsMissingAndUnchangedSignedUnlockingScriptsPerInput(
        _ failureCase: SignedUnlockingScriptFailureCase
    ) throws {
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x54),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data([0x00]),
                    sequence: 0xFFFFFFFF
                ),
                .init(
                    previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x55),
                    previousTransactionOutputIndex: 1,
                    unlockingScript: Data([0x00]),
                    sequence: 0xFFFFFFFE
                )
            ],
            outputs: [
                .init(value: 9_000, lockingScript: Data([0x51]))
            ],
            lockTime: 0
        )
        let envelope = OpalBase.WalletUnsignedTransactionEnvelope(
            unsignedTransaction: unsignedTransaction,
            spentOutputs: [
                .init(value: 5_000, lockingScript: Data([0x51])),
                .init(value: 5_000, lockingScript: Data([0x51]))
            ]
        )

        let signedTransaction = failureCase.makeTransaction(
            from: unsignedTransaction
        )

        #expect(
            throws: failureCase.expectedError
        ) {
            try envelope.validateSignedTransactionStructure(signedTransaction)
        }
    }

    @Test(
        "unsigned transaction envelope rejects invalid unsigned transaction structure",
        arguments: InvalidUnsignedTransactionStructureCase.allCases
    )
    func unsignedTransactionEnvelopeRejectsInvalidUnsignedTransactionStructure(
        _ invalidStructureCase: InvalidUnsignedTransactionStructureCase
    ) {
        let unsignedTransaction = invalidStructureCase.unsignedTransaction
        let signedTransaction = invalidStructureCase.signedTransaction
        let envelope = OpalBase.WalletUnsignedTransactionEnvelope(
            unsignedTransaction: unsignedTransaction,
            spentOutputs: invalidStructureCase.spentOutputs
        )

        #expect(
            throws: invalidStructureCase.expectedError
        ) {
            try envelope.validateSignedTransactionStructure(signedTransaction)
        }
    }

    @Test(
        "unsigned transaction envelope rejects tampered transaction structure",
        arguments: SignedTransactionTamperingCase.allCases
    )
    func unsignedTransactionEnvelopeRejectsTamperedTransactionStructure(
        _ tamperingCase: SignedTransactionTamperingCase
    ) throws {
        let unsignedTransaction = OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x56),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data(),
                    sequence: 0xFFFFFFFF
                )
            ],
            outputs: [
                .init(value: 9_000, lockingScript: Data([0x51]))
            ],
            lockTime: 0
        )
        let envelope = OpalBase.WalletUnsignedTransactionEnvelope(
            unsignedTransaction: unsignedTransaction,
            spentOutputs: [
                .init(value: 10_000, lockingScript: Data([0x51]))
            ]
        )
        let signedTransaction = Self.makeSignedTransaction(matching: unsignedTransaction) { _, _ in
            Data([0x41])
        }
        let signedInput = try #require(signedTransaction.inputs.first)

        let tamperedTransaction = tamperingCase.makeTransaction(
            from: signedTransaction,
            signedInput: signedInput
        )

        #expect(
            throws: OpalBase.WalletUnsignedTransactionEnvelope.Error.signedTransactionDoesNotMatchEnvelope
        ) {
            try envelope.validateSignedTransactionStructure(tamperedTransaction)
        }
    }

    @Test("external review spend plan completes reservation after signed transaction validation")
    func externalReviewSpendPlanCompletesReservationAfterSignedTransactionValidation() async throws {
        let account = try await SpendPlanBroadcastAccountFixture.makeAccountWithoutOutputRandomization()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 45_000,
            hashByte: 0x53
        )
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
                    amount: try OpalBase.Satoshi(15_000)
                )
            ]
        )
        let authoring = OpalBase.WalletTransactionAuthoringInteractor(privateAccount: account)

        let plan = try await authoring.prepareSpendForExternalReview(payment)
        let unsignedTransaction = plan.envelope.unsignedTransaction
        let signedTransaction = Self.makeSignedTransaction(matching: unsignedTransaction) { _, _ in
            Data([0x41])
        }

        let completedTransaction = try await plan.completeExternalSigning(with: signedTransaction)

        #expect(completedTransaction.inputs.count == signedTransaction.inputs.count)
        #expect(plan.envelope.hasMatchingInputAndSpentOutputCounts)
        #expect(plan.inputs == [selectedInput])
        #expect(await account.addressBook.listUTXOs().contains(selectedInput) == false)
        #expect(await account.addressBook.listSpendableUTXOs().contains(selectedInput) == false)
    }

    @Test("external review spend plan rejects released reservation completion")
    func externalReviewSpendPlanRejectsReleasedReservationCompletion() async throws {
        let account = try await SpendPlanBroadcastAccountFixture.makeAccountWithoutOutputRandomization()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 45_000,
            hashByte: 0x5C
        )
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
                    amount: try OpalBase.Satoshi(15_000)
                )
            ]
        )
        let authoring = OpalBase.WalletTransactionAuthoringInteractor(privateAccount: account)
        let plan = try await authoring.prepareSpendForExternalReview(payment)
        let activeReservation = try #require(await account.addressBook.readActiveSpendReservations().first)
        try await account.addressBook.releaseSpendReservation(activeReservation, outcome: .cancelled)
        let unsignedTransaction = plan.envelope.unsignedTransaction
        let signedTransaction = Self.makeSignedTransaction(matching: unsignedTransaction) { _, _ in
            Data([0x41])
        }

        try await Self.requireAccountTransactionBuildFailure(
            underlying: OpalBase.Address.Book.Error.spendReservationNotFound
        ) {
            _ = try await plan.completeExternalSigning(with: signedTransaction)
        }

        #expect(await account.addressBook.readActiveSpendReservations().isEmpty)
        #expect(await account.addressBook.listSpendableUTXOs().contains(selectedInput))
    }

    @Test("external review spend plan inputs match unsigned transaction order")
    func externalReviewSpendPlanInputsMatchUnsignedTransactionOrder() async throws {
        let account = try await SpendPlanBroadcastAccountFixture.makeAccountWithoutOutputRandomization()
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 50_000,
            hashByte: 0x90
        )
        _ = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 30_000,
            hashByte: 0x10
        )
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
                    amount: try OpalBase.Satoshi(60_000)
                )
            ]
        )
        let authoring = OpalBase.WalletTransactionAuthoringInteractor(privateAccount: account)

        let plan = try await authoring.prepareSpendForExternalReview(payment)
        let planInputOutpoints = plan.inputs.map(TransactionOutpoint.init)
        let envelopeInputOutpoints = plan.envelope.unsignedTransaction.inputs.map(TransactionOutpoint.init)

        #expect(plan.inputs.count == 2)
        #expect(planInputOutpoints == envelopeInputOutpoints)
        #expect(plan.inputs.first?.previousTransactionHash == AccountTestFixtures.makeHash(byte: 0x10))
    }

    @Test(
        "external review spend preparation rejects unsupported signing options before reserving inputs",
        arguments: UnsupportedExternalReviewSpendPreparationCase.allCases
    )
    func externalReviewSpendPreparationRejectsUnsupportedSigningOptionsBeforeReservingInputs(
        _ rejectionCase: UnsupportedExternalReviewSpendPreparationCase
    ) async throws {
        let account = try await SpendPlanBroadcastAccountFixture.makeAccountWithoutOutputRandomization()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 45_000,
            hashByte: rejectionCase.hashByte
        )
        let payment = OpalBase.Account.Payment(
            recipients: [
                .init(
                    address: try OpalBase.Address(AccountTestFixtures.standardAddressString),
                    amount: try OpalBase.Satoshi(15_000)
                )
            ]
        )
        let authoring = OpalBase.WalletTransactionAuthoringInteractor(privateAccount: account)

        await rejectionCase.expectRejectedByExternalReviewPreparation(
            authoring: authoring,
            payment: payment,
            selectedInput: selectedInput
        )

        #expect(await account.addressBook.listUTXOs().contains(selectedInput))
        #expect(await account.addressBook.listSpendableUTXOs().contains(selectedInput))
    }

    enum UnsupportedExternalReviewSpendPreparationCase: CaseIterable, CustomStringConvertible, Sendable {
        case rawECDSASignatureFormat
        case hashTypeWithAnyoneCanPayAndUnspentOutputs

        var description: String {
            switch self {
            case .rawECDSASignatureFormat:
                "raw ECDSA signature format"
            case .hashTypeWithAnyoneCanPayAndUnspentOutputs:
                "hash type with ANYONECANPAY and UTXO coverage"
            }
        }

        var hashByte: UInt8 {
            switch self {
            case .rawECDSASignatureFormat:
                0x59
            case .hashTypeWithAnyoneCanPayAndUnspentOutputs:
                0x5B
            }
        }

        func expectRejectedByExternalReviewPreparation(
            authoring: OpalBase.WalletTransactionAuthoringInteractor,
            payment: OpalBase.Account.Payment,
            selectedInput: OpalBase.Transaction.Output.Unspent
        ) async {
            switch self {
            case .rawECDSASignatureFormat:
                await #expect(throws: OpalBase.Transaction.Error.unsupportedSignatureFormat) {
                    _ = try await authoring.prepareSpendForExternalReview(
                        payment,
                        signatureFormat: .ecdsa(.raw)
                    )
                }
            case .hashTypeWithAnyoneCanPayAndUnspentOutputs:
                let unsupportedHashType = OpalBase.Transaction.HashType.makeAll(
                    anyoneCanPay: true,
                    includesUnspentTransactionOutputs: true
                )
                await #expect(throws: OpalBase.Transaction.Error.unsupportedHashType) {
                    _ = try await authoring.prepareSpendForExternalReview(
                        payment,
                        unlockers: [
                            selectedInput: .p2pkh_CheckSig(hashType: unsupportedHashType)
                        ]
                    )
                }
            }
        }
    }

    enum SecretLaneProtectedMaterialResetFailure: Swift.Error, Equatable {
        case resetInvoked
    }

    static func makeSecureEnclaveModeSecurity(
        protectedMaterialReset: (@Sendable () throws -> Void)? = nil
    ) -> OpalBase.Storage.Security {
        .init(
            encrypt: { plaintext in
                .init(mode: .secureEnclave, payload: plaintext)
            },
            decrypt: { ciphertext in
                ciphertext.payload
            },
            protectedMaterialReset: protectedMaterialReset
        )
    }

    static func makeSignedTransaction(
        matching unsignedTransaction: OpalBase.Transaction,
        unlockingScript: (Int, OpalBase.Transaction.Input) -> Data
    ) -> OpalBase.Transaction {
        OpalBase.Transaction(
            version: unsignedTransaction.version,
            inputs: unsignedTransaction.inputs.enumerated().map { index, input in
                OpalBase.Transaction.Input(
                    previousTransactionHash: input.previousTransactionHash,
                    previousTransactionOutputIndex: input.previousTransactionOutputIndex,
                    unlockingScript: unlockingScript(index, input),
                    sequence: input.sequence
                )
            },
            outputs: unsignedTransaction.outputs,
            lockTime: unsignedTransaction.lockTime
        )
    }

    static func requireStoragePersistenceFailure<Underlying>(
        underlying expectedUnderlying: Underlying,
        operation: () async throws -> Void
    ) async throws where Underlying: Swift.Error & Equatable {
        do {
            try await operation()
            throw ExpectedWrapperErrorNotThrown.storagePersistenceFailure
        } catch OpalBase.Storage.Error.persistenceFailure(let underlying) {
            let typedUnderlying = try #require(underlying as? Underlying)
            #expect(typedUnderlying == expectedUnderlying)
        }
    }

    static func requireAccountTransactionBuildFailure(
        underlying expectedUnderlying: OpalBase.Address.Book.Error,
        operation: () async throws -> Void
    ) async throws {
        do {
            try await operation()
            throw ExpectedWrapperErrorNotThrown.accountTransactionBuildFailure
        } catch OpalBase.Account.Error.transactionBuildFailed(let underlying) {
            let typedUnderlying = try #require(underlying as? OpalBase.Address.Book.Error)
            #expect(typedUnderlying == expectedUnderlying)
        }
    }

    enum ExpectedWrapperErrorNotThrown: Swift.Error, CustomStringConvertible {
        case storagePersistenceFailure
        case accountTransactionBuildFailure

        var description: String {
            switch self {
            case .storagePersistenceFailure:
                "Expected a storage persistence failure."
            case .accountTransactionBuildFailure:
                "Expected an account transaction build failure."
            }
        }
    }

    enum SecretLaneWipeFailure: Swift.Error, Equatable {
        case committedGenerationDeleteFailed
    }

    enum SecretLaneInteractorConstructionCase: CaseIterable, CustomStringConvertible, Sendable {
        case storage
        case persistenceSession

        var description: String { slug }

        var slug: String {
            switch self {
            case .storage:
                "storage"
            case .persistenceSession:
                "persistence-session"
            }
        }

        func makeSecretAccessInteractor(
            storage: OpalBase.Storage
        ) async -> OpalBase.WalletSecretAccessInteractor {
            switch self {
            case .storage:
                return await OpalBase.WalletSecretAccessInteractor(storage: storage)
            case .persistenceSession:
                let persistenceSession = await OpalBase.Storage.PersistenceSession(storage: storage)
                return OpalBase.WalletSecretAccessInteractor(persistenceSession: persistenceSession)
            }
        }
    }

    struct TransactionOutpoint: Equatable, Sendable, CustomStringConvertible {
        let hash: OpalBase.Transaction.Hash
        let outputIndex: UInt32

        var description: String {
            "\(hash.reverseOrder.hexadecimalString):\(outputIndex)"
        }

        init(_ input: OpalBase.Transaction.Input) {
            self.hash = input.previousTransactionHash
            self.outputIndex = input.previousTransactionOutputIndex
        }

        init(_ unspentOutput: OpalBase.Transaction.Output.Unspent) {
            self.hash = unspentOutput.previousTransactionHash
            self.outputIndex = unspentOutput.previousTransactionOutputIndex
        }
    }

    enum InvalidUnsignedTransactionStructureCase: CaseIterable, CustomStringConvertible, Sendable {
        case inputless
        case duplicateInputs
        case outputless

        var description: String {
            switch self {
            case .inputless:
                "inputless"
            case .duplicateInputs:
                "duplicate inputs"
            case .outputless:
                "outputless"
            }
        }

        var unsignedTransaction: OpalBase.Transaction {
            switch self {
            case .inputless:
                return OpalBase.Transaction(
                    version: 2,
                    inputs: [],
                    outputs: [
                        .init(value: 9_000, lockingScript: Data([0x51]))
                    ],
                    lockTime: 0
                )
            case .duplicateInputs:
                let duplicateInput = OpalBase.Transaction.Input(
                    previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x5D),
                    previousTransactionOutputIndex: 0,
                    unlockingScript: Data([0x00]),
                    sequence: 0xFFFFFFFF
                )
                return OpalBase.Transaction(
                    version: 2,
                    inputs: [duplicateInput, duplicateInput],
                    outputs: [
                        .init(value: 9_000, lockingScript: Data([0x51]))
                    ],
                    lockTime: 0
                )
            case .outputless:
                return OpalBase.Transaction(
                    version: 2,
                    inputs: [
                        .init(
                            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x5C),
                            previousTransactionOutputIndex: 0,
                            unlockingScript: Data([0x00]),
                            sequence: 0xFFFFFFFF
                        )
                    ],
                    outputs: [],
                    lockTime: 0
                )
            }
        }

        var signedTransaction: OpalBase.Transaction {
            switch self {
            case .inputless:
                unsignedTransaction
            case .duplicateInputs:
                WalletSecurityProfileValidator.makeSignedTransaction(matching: unsignedTransaction) { _, _ in
                    Data([0x41])
                }
            case .outputless:
                WalletSecurityProfileValidator.makeSignedTransaction(matching: unsignedTransaction) { _, _ in
                    Data([0x41])
                }
            }
        }

        var spentOutputs: [OpalBase.Transaction.Output] {
            switch self {
            case .inputless:
                []
            case .duplicateInputs:
                [
                    .init(value: 5_000, lockingScript: Data([0x51])),
                    .init(value: 5_000, lockingScript: Data([0x51]))
                ]
            case .outputless:
                [
                    .init(value: 10_000, lockingScript: Data([0x51]))
                ]
            }
        }

        var expectedError: OpalBase.WalletUnsignedTransactionEnvelope.Error {
            switch self {
            case .inputless:
                .unsignedTransactionHasNoInputs
            case .duplicateInputs:
                .unsignedTransactionHasDuplicateInputs
            case .outputless:
                .unsignedTransactionHasNoOutputs
            }
        }
    }

    actor FailingCommittedGenerationDeleteValueStorage {
        private var values: [String: Data] = .init()

        nonisolated func makeValueClient() -> OpalBase.Storage.ValueClient {
            .init(
                valueWriter: { data, key in
                    await self.store(data, key: key)
                },
                valueReader: { key in
                    await self.load(key: key)
                },
                valueDeleter: { key in
                    try await self.delete(key: key)
                },
                allValuesDeleter: {
                    await self.deleteAll()
                }
            )
        }

        private func store(_ data: Data, key: OpalBase.Storage.Key) {
            values[key.rawValue] = Data(data)
        }

        private func load(key: OpalBase.Storage.Key) -> Data? {
            values[key.rawValue].map { Data($0) }
        }

        private func delete(key: OpalBase.Storage.Key) throws {
            if key.rawValue == OpalBase.Storage.Key.walletSnapshotCommittedGeneration.rawValue {
                throw SecretLaneWipeFailure.committedGenerationDeleteFailed
            }
            values.removeValue(forKey: key.rawValue)
        }

        private func deleteAll() {
            values.removeAll()
        }
    }

    enum SignedTransactionTamperingCase: CaseIterable, CustomStringConvertible, Sendable {
        case version
        case inputOutpoint
        case inputSequence
        case output
        case lockTime

        var description: String {
            switch self {
            case .version:
                "version"
            case .inputOutpoint:
                "input outpoint"
            case .inputSequence:
                "input sequence"
            case .output:
                "output"
            case .lockTime:
                "lock time"
            }
        }

        func makeTransaction(
            from signedTransaction: OpalBase.Transaction,
            signedInput: OpalBase.Transaction.Input
        ) -> OpalBase.Transaction {
            switch self {
            case .version:
                OpalBase.Transaction(
                    version: 3,
                    inputs: signedTransaction.inputs,
                    outputs: signedTransaction.outputs,
                    lockTime: signedTransaction.lockTime
                )
            case .inputOutpoint:
                OpalBase.Transaction(
                    version: signedTransaction.version,
                    inputs: [
                        .init(
                            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x57),
                            previousTransactionOutputIndex: signedInput.previousTransactionOutputIndex,
                            unlockingScript: signedInput.unlockingScript,
                            sequence: signedInput.sequence
                        )
                    ],
                    outputs: signedTransaction.outputs,
                    lockTime: signedTransaction.lockTime
                )
            case .inputSequence:
                OpalBase.Transaction(
                    version: signedTransaction.version,
                    inputs: [
                        .init(
                            previousTransactionHash: signedInput.previousTransactionHash,
                            previousTransactionOutputIndex: signedInput.previousTransactionOutputIndex,
                            unlockingScript: signedInput.unlockingScript,
                            sequence: signedInput.sequence - 1
                        )
                    ],
                    outputs: signedTransaction.outputs,
                    lockTime: signedTransaction.lockTime
                )
            case .output:
                OpalBase.Transaction(
                    version: signedTransaction.version,
                    inputs: signedTransaction.inputs,
                    outputs: [.init(value: 8_999, lockingScript: Data([0x51]))],
                    lockTime: signedTransaction.lockTime
                )
            case .lockTime:
                OpalBase.Transaction(
                    version: signedTransaction.version,
                    inputs: signedTransaction.inputs,
                    outputs: signedTransaction.outputs,
                    lockTime: 1
                )
            }
        }
    }

    enum UnsupportedSignatureFormatBoundaryCase: CaseIterable, CustomStringConvertible, Sendable {
        case unsignedEnvelopeBuild
        case signedEnvelopeValidation

        var description: String {
            switch self {
            case .unsignedEnvelopeBuild:
                "unsigned envelope build"
            case .signedEnvelopeValidation:
                "signed envelope validation"
            }
        }

        func validateUnsupportedRawECDSARejection() throws {
            switch self {
            case .unsignedEnvelopeBuild:
                let unspentOutput = OpalBase.Transaction.Output.Unspent(
                    output: .init(
                        value: 10_000,
                        lockingScript: Data([0x51])
                    ),
                    previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x58),
                    previousTransactionOutputIndex: 0
                )

                #expect(throws: OpalBase.Transaction.Error.unsupportedSignatureFormat) {
                    _ = try OpalBase.Transaction.makeUnsignedTransactionEnvelope(
                        unspentOutputs: [unspentOutput],
                        recipientOutputs: [
                            .init(value: 9_000, lockingScript: Data([0x51]))
                        ],
                        changeOutput: .init(value: 500, lockingScript: Data([0x51])),
                        signatureFormat: .ecdsa(.raw)
                    )
                }
            case .signedEnvelopeValidation:
                let unsignedTransaction = OpalBase.Transaction(
                    version: 2,
                    inputs: [
                        .init(
                            previousTransactionHash: AccountTestFixtures.makeHash(byte: 0x5A),
                            previousTransactionOutputIndex: 0,
                            unlockingScript: Data([0x00]),
                            sequence: 0xFFFFFFFF
                        )
                    ],
                    outputs: [
                        .init(value: 9_000, lockingScript: Data([0x51]))
                    ],
                    lockTime: 0
                )
                let signedTransaction = WalletSecurityProfileValidator.makeSignedTransaction(
                    matching: unsignedTransaction
                ) { _, _ in
                    Data([0x41])
                }
                let envelope = OpalBase.WalletUnsignedTransactionEnvelope(
                    unsignedTransaction: unsignedTransaction,
                    spentOutputs: [
                        .init(value: 10_000, lockingScript: Data([0x51]))
                    ],
                    signatureFormat: .ecdsa(.raw)
                )

                #expect(
                    throws: OpalBase.WalletUnsignedTransactionEnvelope.Error.unsupportedSignatureFormat
                ) {
                    try envelope.validateSignedTransactionStructure(signedTransaction)
                }
            }
        }
    }

    struct SignedUnlockingScriptFailureCase: CaseIterable, CustomStringConvertible, Sendable {
        enum Kind: String, Sendable {
            case missing
            case unchanged
        }

        let kind: Kind
        let failingInputIndex: Int

        static let allCases: [Self] = [
            .init(kind: .missing, failingInputIndex: 0),
            .init(kind: .unchanged, failingInputIndex: 0),
            .init(kind: .missing, failingInputIndex: 1),
            .init(kind: .unchanged, failingInputIndex: 1),
        ]

        var description: String {
            "\(kind.rawValue) input \(failingInputIndex)"
        }

        var expectedError: OpalBase.WalletUnsignedTransactionEnvelope.Error {
            switch kind {
            case .missing:
                .missingSignedUnlockingScript(inputIndex: failingInputIndex)
            case .unchanged:
                .unchangedSignedUnlockingScript(inputIndex: failingInputIndex)
            }
        }

        func makeTransaction(
            from unsignedTransaction: OpalBase.Transaction
        ) -> OpalBase.Transaction {
            WalletSecurityProfileValidator.makeSignedTransaction(matching: unsignedTransaction) { index, input in
                let unlockingScript: Data
                if index == failingInputIndex {
                    unlockingScript = kind == .missing ? Data() : input.unlockingScript
                } else {
                    unlockingScript = Data([UInt8(0x41 + index)])
                }

                return unlockingScript
            }
        }
    }
}
