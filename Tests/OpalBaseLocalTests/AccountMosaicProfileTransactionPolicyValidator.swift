// AccountMosaicProfileTransactionPolicyValidator.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account Mosaic profile transaction policy", .tags(.unit, .wallet, .transaction))
struct AccountMosaicProfileTransactionPolicyValidator {
    typealias Failure = OpalBase.Account.MosaicProfileTransactionPolicy.Failure
    typealias Fixture = MosaicProfileTransactionPolicyFixture

    @Test("The profile fetches every previous transaction and accepts the exact final-size fee")
    func acceptValidProfileTransaction() async throws {
        let materials = try [
            Fixture.makeInputMaterial(seed: 1, amountSatoshis: 80_000),
            Fixture.makeInputMaterial(seed: 2, amountSatoshis: 70_000)
        ].sorted {
            $0.transactionHash.reverseOrder.lexicographicallyPrecedes(
                $1.transactionHash.reverseOrder
            )
        }
        let rawTransactions = Dictionary(
            uniqueKeysWithValues: materials.map {
                ($0.transactionHash, $0.rawPreviousTransaction)
            }
        )
        let probe = PreviousTransactionProbe(rawTransactions: rawTransactions)
        let reader = OpalBase.Network.TransactionReader { transactionHash in
            try await probe.fetch(transactionHash)
        }
        let scenario = try Fixture.makeScenario(
            materials: materials,
            transactionReader: reader
        )
        let policy = try OpalBase.Account.MosaicTransactionPolicy(
            profile: .opalV0,
            network: .chipnet,
            transactionReader: reader
        )

        try await policy.validate(
            transaction: scenario.transaction,
            request: scenario.request,
            feeSatoshis: scenario.feeSatoshis
        )

        #expect(scenario.feeSatoshis == 326)
        #expect(await probe.requestedHashes == materials.map(\.transactionHash))
    }

    @Test("Mainnet alpha applies the same exact transaction rules")
    func acceptValidMainnetAlphaTransaction() async throws {
        let scenario = try Fixture.makeScenario(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )

        try await validate(scenario)
    }

    @Test("Remote public keys may be deferred, but local public keys are required")
    func validateDeferredRemotePublicKeys() async throws {
        let materials = try [
            Fixture.makeInputMaterial(seed: 3, amountSatoshis: 80_000),
            Fixture.makeInputMaterial(seed: 4, amountSatoshis: 70_000)
        ].sorted {
            $0.transactionHash.reverseOrder.lexicographicallyPrecedes(
                $1.transactionHash.reverseOrder
            )
        }
        let localInput = materials[0].participantInput
        let remoteInput = participantInputWithoutPublicKey(
            materials[1].participantInput
        )
        let remoteDeferred = try Fixture.makeScenario(
            materials: materials,
            spentInputs: [localInput, remoteInput]
        )

        try await validate(remoteDeferred)

        let localMissing = try Fixture.makeScenario(
            materials: materials,
            spentInputs: [
                participantInputWithoutPublicKey(localInput),
                materials[1].participantInput
            ]
        )
        await #expect(throws: Failure.invalidInput(index: 0)) {
            try await validate(localMissing)
        }
    }

    @Test("Exactly two profile and network pairs can construct a policy")
    func validateSupportedProfileNetworkPairs() throws {
        let reader = OpalBase.Network.TransactionReader { _ in Data() }
        let profiles: [OpalFusion.Mosaic.Profile] = [
            .draft1,
            .opalV0,
            .opalMainnetAlpha
        ]
        let networks: [OpalBase.Network.Environment] = [
            .mainnet,
            .testnet,
            .chipnet
        ]

        for profile in profiles {
            for network in networks {
                let isSupported = (profile == .opalV0 && network == .chipnet)
                    || (profile == .opalMainnetAlpha && network == .mainnet)
                if isSupported {
                    _ = try OpalBase.Account.MosaicProfileTransactionPolicy(
                        profile: profile,
                        network: network,
                        transactionReader: reader
                    )
                } else {
                    #expect(throws: Failure.unsupportedProfileNetworkPair) {
                        _ = try OpalBase.Account.MosaicProfileTransactionPolicy(
                            profile: profile,
                            network: network,
                            transactionReader: reader
                        )
                    }
                }
            }
        }
    }

    @Test("Profile, transcript, transaction-profile, and fee-term substitutions fail closed")
    func rejectBindingAndTermSubstitutions() async throws {
        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .unsupportedProfile(.draft1)
        ) {
            _ = try Fixture.makeScenario(profile: .draft1)
        }

        let valid = try Fixture.makeScenario()
        let substitutedTransaction = OpalBase.Transaction(
            version: 3,
            inputs: valid.transaction.inputs,
            outputs: valid.transaction.outputs,
            lockTime: valid.transaction.lockTime
        )
        await #expect(throws: Failure.invalidTranscriptBinding) {
            try await valid.policy.validate(
                transaction: substitutedTransaction,
                request: valid.request,
                feeSatoshis: valid.feeSatoshis
            )
        }

        #expect(
            throws: OpalFusion.Host.MosaicHostContractError
                .transactionProfileIdentifierMismatch(
                    expected: OpalFusion.Mosaic.Profile.opalV0
                        .transactionProfileIdentifier,
                    actual: "different-profile"
                )
        ) {
            _ = try Fixture.makeScenario(
                transactionProfileIdentifier: "different-profile"
            )
        }

        let wrongRate = try Fixture.makeScenario(feeRateSatoshisPerByte: 2)
        await #expect(throws: Failure.invalidFeeTerms) {
            try await validate(wrongRate)
        }
        let wrongMinimum = try Fixture.makeScenario(
            minimumExcessFeeSatoshis: 1,
            maximumExcessFeeSatoshis: 1
        )
        await #expect(throws: Failure.invalidFeeTerms) {
            try await validate(wrongMinimum)
        }
        let wrongMaximum = try Fixture.makeScenario(maximumExcessFeeSatoshis: 1)
        await #expect(throws: Failure.invalidFeeTerms) {
            try await validate(wrongMaximum)
        }

        let mainnetPolicy = try OpalBase.Account.MosaicProfileTransactionPolicy(
            profile: .opalMainnetAlpha,
            network: .mainnet,
            transactionReader: .init { _ in Data() }
        )
        await #expect(throws: Failure.incompatibleProfile) {
            try await mainnetPolicy.validate(
                transaction: valid.transaction,
                request: valid.request,
                feeSatoshis: valid.feeSatoshis
            )
        }

        let mainnetScenario = try Fixture.makeScenario(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        let chipnetPolicy = try OpalBase.Account.MosaicProfileTransactionPolicy(
            profile: .opalV0,
            network: .chipnet,
            transactionReader: .init { _ in Data() }
        )
        await #expect(throws: Failure.incompatibleProfile) {
            try await chipnetPolicy.validate(
                transaction: mainnetScenario.transaction,
                request: mainnetScenario.request,
                feeSatoshis: mainnetScenario.feeSatoshis
            )
        }
    }

    @Test("Version, lock time, input count, unlocking scripts, and sequences are exact")
    func rejectInvalidHeaderAndInputShape() async throws {
        let wrongVersion = try Fixture.makeScenario(version: 1)
        await #expect(throws: Failure.invalidVersion) {
            try await validate(wrongVersion)
        }

        let wrongLockTime = try Fixture.makeScenario(lockTime: 1)
        await #expect(throws: Failure.invalidLockTime) {
            try await validate(wrongLockTime)
        }

        let material = try Fixture.makeInputMaterial()
        let wrongCount = try Fixture.makeScenario(
            materials: [material],
            spentInputs: [material.participantInput, material.participantInput]
        )
        await #expect(throws: Failure.invalidInputCount) {
            try await validate(wrongCount)
        }

        let nonEmptyUnlockingScript = OpalBase.Transaction.Input(
            previousTransactionHash: material.transactionHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data([0x51])
        )
        let signedProposal = try Fixture.makeScenario(
            materials: [material],
            transactionInputs: [nonEmptyUnlockingScript]
        )
        await #expect(throws: Failure.invalidInput(index: 0)) {
            try await validate(signedProposal)
        }

        let invalidParticipantInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: material.participantInput.outpointTransactionHashBytes,
            outpointIndex: material.participantInput.outpointIndex,
            amountSatoshis: material.participantInput.amountSatoshis,
            lockingScriptBytes: [0x51],
            publicKey: material.participantInput.publicKey
        )
        let nonP2PKHInput = try Fixture.makeScenario(
            materials: [material],
            spentInputs: [invalidParticipantInput]
        )
        await #expect(throws: Failure.invalidInput(index: 0)) {
            try await validate(nonP2PKHInput)
        }

        let wrongSequenceInput = OpalBase.Transaction.Input(
            previousTransactionHash: material.transactionHash,
            previousTransactionOutputIndex: 0,
            unlockingScript: Data(),
            sequence: UInt32.max - 1
        )
        let wrongSequence = try Fixture.makeScenario(
            materials: [material],
            transactionInputs: [wrongSequenceInput]
        )
        await #expect(throws: Failure.invalidInputSequence(index: 0)) {
            try await validate(wrongSequence)
        }
    }

    @Test("Inputs use display-order outpoints and outputs use amount-then-script ordering")
    func rejectNonCanonicalOrdering() async throws {
        let sortedMaterials = try [
            Fixture.makeInputMaterial(seed: 3, amountSatoshis: 60_000),
            Fixture.makeInputMaterial(seed: 4, amountSatoshis: 60_000)
        ].sorted {
            $0.transactionHash.reverseOrder.lexicographicallyPrecedes(
                $1.transactionHash.reverseOrder
            )
        }
        let reversedInputs = try Fixture.makeScenario(
            materials: Array(sortedMaterials.reversed())
        )
        await #expect(throws: Failure.invalidInputOrdering) {
            try await validate(reversedInputs)
        }

        let firstScript = try Fixture.makeP2PKHLockingScript(seed: 0x21)
        let secondScript = try Fixture.makeP2PKHLockingScript(seed: 0x22)
        let descendingAmounts = try Fixture.makeScenario(
            outputs: [
                .init(value: 50_000, lockingScript: firstScript),
                .init(value: 40_000, lockingScript: secondScript)
            ]
        )
        await #expect(throws: Failure.invalidOutputOrdering) {
            try await validate(descendingAmounts)
        }

        let scripts = [firstScript, secondScript].sorted {
            $0.lexicographicallyPrecedes($1)
        }
        let descendingScripts = try Fixture.makeScenario(
            outputs: [
                .init(value: 40_000, lockingScript: scripts[1]),
                .init(value: 40_000, lockingScript: scripts[0])
            ]
        )
        await #expect(throws: Failure.invalidOutputOrdering) {
            try await validate(descendingScripts)
        }
    }

    @Test("Every input and output must be standard token-free P2PKH")
    func rejectNonStandardOrTokenBearingOutputs() async throws {
        let markerOutput = try Fixture.makeScenario(
            outputs: [.init(value: 99_000, lockingScript: Data([0x6a]))]
        )
        await #expect(throws: Failure.invalidOutput(index: 0)) {
            try await validate(markerOutput)
        }

        let tokenOutput = try Fixture.makeScenario(
            outputs: [
                .init(
                    value: 99_000,
                    lockingScript: Fixture.makeP2PKHLockingScript(seed: 0x23),
                    tokenData: CashFusionTestSupport.makeTokenData()
                )
            ]
        )
        await #expect(throws: Failure.invalidOutput(index: 0)) {
            try await validate(tokenOutput)
        }
    }

    @Test("Previous-transaction fetch, hash, decoding, and output-index failures are distinct")
    func rejectUnavailableOrInvalidPreviousTransactions() async throws {
        let unavailableReader = OpalBase.Network.TransactionReader { _ in
            throw Fixture.FixtureFailure.unavailable
        }
        let unavailable = try Fixture.makeScenario(transactionReader: unavailableReader)
        await #expect(throws: Failure.previousTransactionUnavailable(index: 0)) {
            try await validate(unavailable)
        }

        let cancellationReader = OpalBase.Network.TransactionReader { _ in
            throw CancellationError()
        }
        let cancelled = try Fixture.makeScenario(transactionReader: cancellationReader)
        await #expect(throws: CancellationError.self) {
            try await validate(cancelled)
        }

        let differentMaterial = try Fixture.makeInputMaterial(seed: 8)
        let hashMismatchReader = OpalBase.Network.TransactionReader { _ in
            differentMaterial.rawPreviousTransaction
        }
        let hashMismatch = try Fixture.makeScenario(transactionReader: hashMismatchReader)
        await #expect(throws: Failure.previousTransactionHashMismatch(index: 0)) {
            try await validate(hashMismatch)
        }

        let malformedMaterial = try Fixture.makeInputMaterial(
            rawPreviousTransactionOverride: Data([0x00, 0x01])
        )
        let malformed = try Fixture.makeScenario(materials: [malformedMaterial])
        await #expect(throws: Failure.invalidPreviousTransaction(index: 0)) {
            try await validate(malformed)
        }

        let ordinaryMaterial = try Fixture.makeInputMaterial(seed: 9)
        let trailingMaterial = try Fixture.makeInputMaterial(
            seed: 9,
            rawPreviousTransactionOverride: ordinaryMaterial.rawPreviousTransaction + Data([0])
        )
        let trailing = try Fixture.makeScenario(materials: [trailingMaterial])
        await #expect(throws: Failure.invalidPreviousTransaction(index: 0)) {
            try await validate(trailing)
        }

        let missingOutput = try Fixture.makeInputMaterial(outputIndex: 1)
        let missing = try Fixture.makeScenario(materials: [missingOutput])
        await #expect(throws: Failure.previousOutputUnavailable(index: 0)) {
            try await validate(missing)
        }
    }

    @Test("Previous output amount, locking script, and token state must match exactly")
    func rejectPreviousOutputSubstitutions() async throws {
        let wrongAmount = try Fixture.makeInputMaterial(
            participantAmountSatoshis: 100_001
        )
        let amountScenario = try Fixture.makeScenario(materials: [wrongAmount])
        await #expect(throws: Failure.previousOutputMismatch(index: 0)) {
            try await validate(amountScenario)
        }

        let wrongScript = try Fixture.makeInputMaterial(
            previousOutputLockingScript: Fixture.makeP2PKHLockingScript(seed: 0x24)
        )
        let scriptScenario = try Fixture.makeScenario(materials: [wrongScript])
        await #expect(throws: Failure.previousOutputMismatch(index: 0)) {
            try await validate(scriptScenario)
        }

        let tokenMaterial = try Fixture.makeInputMaterial(
            previousOutputTokenData: CashFusionTestSupport.makeTokenData()
        )
        let tokenScenario = try Fixture.makeScenario(materials: [tokenMaterial])
        await #expect(throws: Failure.previousOutputMismatch(index: 0)) {
            try await validate(tokenScenario)
        }
    }

    @Test("The fee must equal one satoshi per estimated fully signed byte")
    func rejectFeeMismatch() async throws {
        let scenario = try Fixture.makeScenario()
        await #expect(
            throws: Failure.feeMismatch(
                expected: scenario.feeSatoshis,
                actual: scenario.feeSatoshis + 1
            )
        ) {
            try await scenario.policy.validate(
                transaction: scenario.transaction,
                request: scenario.request,
                feeSatoshis: scenario.feeSatoshis + 1
            )
        }
    }

    private func validate(_ scenario: Fixture.Scenario) async throws {
        try await scenario.policy.validate(
            transaction: scenario.transaction,
            request: scenario.request,
            feeSatoshis: scenario.feeSatoshis
        )
    }

    private func participantInputWithoutPublicKey(
        _ input: OpalFusion.Host.ParticipantInput
    ) -> OpalFusion.Host.ParticipantInput {
        .init(
            outpointTransactionHashBytes: input.outpointTransactionHashBytes,
            outpointIndex: input.outpointIndex,
            amountSatoshis: input.amountSatoshis,
            lockingScriptBytes: input.lockingScriptBytes,
            publicKey: nil
        )
    }
}

private actor PreviousTransactionProbe {
    let rawTransactions: [OpalBase.Transaction.Hash: Data]
    private(set) var requestedHashes: [OpalBase.Transaction.Hash] = []

    init(rawTransactions: [OpalBase.Transaction.Hash: Data]) {
        self.rawTransactions = rawTransactions
    }

    func fetch(_ transactionHash: OpalBase.Transaction.Hash) throws -> Data {
        requestedHashes.append(transactionHash)
        guard let rawTransaction = rawTransactions[transactionHash] else {
            throw MosaicProfileTransactionPolicyFixture.FixtureFailure
                .missingPreviousTransaction
        }
        return rawTransaction
    }
}
#endif
