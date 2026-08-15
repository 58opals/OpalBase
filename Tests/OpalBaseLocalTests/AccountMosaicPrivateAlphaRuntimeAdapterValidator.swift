// AccountMosaicPrivateAlphaRuntimeAdapterValidator.swift

#if os(macOS)
import Foundation
@_spi(MosaicPrivateAlpha) import OpalFusion
import Testing
@_spi(MosaicPrivateAlpha) @testable import OpalBase

@Suite("OpalBase.Account Mosaic private-alpha Fusion adapter", .tags(.unit, .wallet))
struct AccountMosaicPrivateAlphaRuntimeAdapterValidator {
    @Test("Fresh creation derives and durably records the sole Fusion binding")
    func createFreshHostWithExactFusionBinding() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            usage: .change,
            hashByte: 0xa2
        )
        let contributionPolicy = try #require(
            OpalBase.Account.MosaicProfileContributionPolicy(
                profile: .opalMainnetAlpha
            )
        )
        let requiredExcessFeeSatoshis = contributionPolicy
            .maximumExcessFeeSatoshis
        let localContribution = try #require(
            contributionPolicy.expectedLocalContributionSatoshis(
                inputCount: 1,
                outputCount: 1,
                requiredExcessFeeSatoshis: requiredExcessFeeSatoshis
            )
        )
        let journalProbe = MosaicAttemptJournalProbeActor()
        let journalAttempt = OpalBase.Account.MosaicPrivateAlphaJournal
            .FreshAttempt(try await journalProbe.makeFreshAttempt())
        let binding = try makeFusionBinding()
        let fusionAttempt = try OpalFusion.MosaicPrivateAlphaRuntime
            .createFreshAttempt(
                boundTo: binding,
                discoveryEpochStartUnixSeconds: 1_800_000_000
            )
        let walletIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000042")
        )

        let host = try await OpalBase.Account.MosaicPrivateAlphaRuntime
            .createFreshHost(
                account: account,
                fusionAttempt: fusionAttempt,
                walletReservationIdentifier: walletIdentifier,
                walletGeneration: 42,
                profile: .opalMainnetAlpha,
                network: .mainnet,
                selectedInputs: [selectedInput],
                outputAmountsSatoshis: [
                    selectedInput.value - localContribution,
                ],
                transactionReader: .init(
                    fetchRawTransaction: { _ in Data() }
                ),
                journalAttempt: journalAttempt
            )

        let records = await journalProbe.readRecords()
        guard case let .attemptBinding(recordedBinding) = records.first,
              records.count == 1 else {
            Issue.record("Expected one durable cross-package binding")
            return
        }
        #expect(recordedBinding.attemptIdentifier == binding.attemptIdentifier)
        #expect(
            recordedBinding.generationIdentifier
                == binding.generationIdentifier
        )
        #expect(
            recordedBinding.materialIdentifier == binding.materialIdentifier
        )
        #expect(
            recordedBinding.walletReservationReference
                == .init(identifier: walletIdentifier, generation: 42)
        )
        guard case let .persist(transition) = try await host
            .privateDeploymentOwner.nextStep() else {
            Issue.record("Expected Fusion's initial durable transition")
            return
        }
        #expect(transition.binding == binding)
    }

    @Test("Recovery rejects every cross-package identity mismatch before wallet mutation")
    func rejectMismatchedRecoveryHandles() async throws {
        try await expectRecoveryBindingRejection(
            fusionIdentifierBytes: (0x99, nil, nil)
        )
        try await expectRecoveryBindingRejection(
            fusionIdentifierBytes: (nil, 0x99, nil)
        )
        try await expectRecoveryBindingRejection(
            fusionIdentifierBytes: (nil, nil, 0x99)
        )
        try await expectRecoveryBindingRejection(
            changesWalletIdentifier: true
        )
        try await expectRecoveryBindingRejection(
            changesWalletGeneration: true
        )
    }

    @Test("Recovery bundle exposes one binding and exact read-only reservation replay")
    func exposeMatchingRecoveryCapabilities() async throws {
        let prepared = try await makeReservedAttempt()
        let baseBinding = await prepared.fixture.host.attemptBinding
        let fusionBinding = try makeFusionBinding(from: baseBinding)
        let fusionRecovery = try await makeFusionRecovery(
            binding: fusionBinding
        )
        let journalRecovery = OpalBase.Account.MosaicPrivateAlphaJournal
            .LoadedRecovery(
                try await prepared.fixture.journalProbe.loadRecovery()
            )
        await prepared.fixture.addressBook.releaseUTXOs(
            [prepared.fixture.selectedInput]
        )
        #expect(
            await prepared.fixture.addressBook.listSpendableUTXOs()
                .contains(prepared.fixture.selectedInput)
        )

        let recovery = try await OpalBase.Account.MosaicPrivateAlphaRuntime
            .loadRecoveryOwner(
                account: prepared.fixture.account,
                expectedWalletReservationIdentifier: baseBinding
                    .walletReservationReference.identifier,
                expectedWalletGeneration: baseBinding
                    .walletReservationReference.generation,
                fusionRecovery: fusionRecovery,
                journalRecovery: journalRecovery
            )
        #expect(recovery.binding == fusionBinding)
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(prepared.fixture.selectedInput)
        )

        guard case let .recover(directive) = try await recovery
            .privateDeploymentOwner.nextStep(),
              case let .resumePrivateDeployment(continuation) = directive else {
            Issue.record("Expected Fusion recovery to remain unclaimed for deterministic replay")
            return
        }
        #expect(continuation.binding == fusionBinding)

        let transactionHost = recovery.transactionHost
        let recordsBeforeReplay = await prepared.fixture.journalProbe
            .readRecords()
        let firstLease = try await transactionHost.reserveMosaicContribution(
            for: prepared.fixture.reservationRequest
        )
        let secondLease = try await transactionHost.reserveMosaicContribution(
            for: prepared.fixture.reservationRequest
        )
        #expect(firstLease == prepared.lease)
        #expect(secondLease == prepared.lease)

        let changedRequest = try changedReservationRequest(
            prepared.fixture.reservationRequest
        )
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .inPlaceRetryNotPermitted
        ) {
            _ = try await transactionHost.reserveMosaicContribution(
                for: changedRequest
            )
        }
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .staleReservationReference
        ) {
            try await transactionHost.releaseMosaicReservation(
                .init(
                    identifier: prepared.lease.reference.identifier,
                    generation: prepared.lease.reference.generation + 1
                )
            )
        }
        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == recordsBeforeReplay
        )
    }

    @Test("Recovered signing intent releases exact wallet state without signer access")
    func releaseRecoveredSigningIntentWithoutSigning() async throws {
        let prepared = try await makeReservedAttempt()
        let signingRequest = try prepared.fixture.makeSigningRequest(
            lease: prepared.lease
        )
        let journal = await prepared.fixture.host.attemptJournal
        try await journal.append(.signingIntent(signingRequest))
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .reconciliationRequired
        ) {
            _ = try await owner.finalizeMosaicTransaction(
                for: signingRequest
            )
        }
        #expect(await prepared.fixture.host.readSigningInvocationCount() == 0)
        #expect(
            await prepared.fixture.addressBook.listSpendableUTXOs()
                .contains(prepared.fixture.selectedInput)
        )
        let recordsAfterRelease = await prepared.fixture.journalProbe
            .readRecords()
        guard case .releaseIntent = recordsAfterRelease.dropLast(2).last,
              case .released = recordsAfterRelease.dropLast().last,
              case .terminalDisposition(_, nil, .walletReleased)
                = recordsAfterRelease.last else {
            Issue.record("Expected durable exact release terminalization")
            return
        }

        try await owner.releaseMosaicReservation(prepared.lease.reference)
        try await owner.releaseMosaicReservation(prepared.lease.reference)
        let historicalLease = try await owner.reserveMosaicContribution(
            for: prepared.fixture.reservationRequest
        )
        #expect(historicalLease == prepared.lease)
        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == recordsAfterRelease
        )
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .terminalReservation
        ) {
            _ = try await owner.finalizeMosaicTransaction(
                for: signingRequest
            )
        }
    }

    @Test("Locally signed replay returns only the exact authenticated result")
    func replayExactLocallySignedResult() async throws {
        let prepared = try await makeLocallySignedAttempt()
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let recordsBeforeReplay = await prepared.fixture.journalProbe
            .readRecords()

        let first = try await owner.finalizeMosaicTransaction(
            for: prepared.request
        )
        let second = try await owner.finalizeMosaicTransaction(
            for: prepared.request
        )
        #expect(first == prepared.finalized)
        #expect(second == prepared.finalized)

        let changedRequest = try prepared.fixture.makeSigningRequest(
            lease: prepared.lease,
            transcriptByte: 0x55
        )
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .conflictingFinalization
        ) {
            _ = try await owner.finalizeMosaicTransaction(
                for: changedRequest
            )
        }
        #expect(await prepared.fixture.host.readSigningInvocationCount() == 1)
        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == recordsBeforeReplay
        )
    }

    @Test("Recovered complete commit reconciles crash cuts and exact retries")
    func reconcileCompleteCommitCrashCut() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(
            failingAppendIndices: [5]
        )
        let prepared = try await makeLocallySignedAttempt(
            journalProbe: journalProbe
        )
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: journalProbe
        )
        let recordsBeforeCommit = await journalProbe.readRecords()
        let staleReference = OpalFusion.Host.MosaicReservationReference(
            identifier: prepared.lease.reference.identifier,
            generation: prepared.lease.reference.generation + 1
        )

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .staleReservationReference
        ) {
            try await owner.commitMosaicReservation(
                staleReference,
                completeTransaction: prepared.complete
            )
        }
        let malformed = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: [0x01]
        )
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .invalidCompleteTransaction
        ) {
            try await owner.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: malformed
            )
        }
        #expect(await journalProbe.readRecords() == recordsBeforeCommit)

        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .replaceFailed
        ) {
            try await owner.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: prepared.complete
            )
        }
        let recordsAtCrash = await journalProbe.readRecords()
        guard case .commitIntent(
            prepared.lease.reference,
            prepared.complete
        ) = recordsAtCrash.last else {
            Issue.record("Expected write-ahead commit intent at crash cut")
            return
        }
        #expect(
            !(await prepared.fixture.addressBook.listUTXOs())
                .contains(prepared.fixture.selectedInput)
        )

        try await owner.commitMosaicReservation(
            prepared.lease.reference,
            completeTransaction: prepared.complete
        )
        let committedRecords = await journalProbe.readRecords()
        guard case .committed(
            prepared.lease.reference,
            prepared.complete
        ) = committedRecords.last else {
            Issue.record("Expected exact commit reconciliation")
            return
        }

        try await owner.commitMosaicReservation(
            prepared.lease.reference,
            completeTransaction: prepared.complete
        )
        try await owner.commitMosaicReservation(
            prepared.lease.reference,
            finalizedTransaction: prepared.finalized
        )
        #expect(await journalProbe.readRecords() == committedRecords)

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .conflictingCompleteTransaction
        ) {
            try await owner.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: malformed
            )
        }
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .completeTransactionRequired
        ) {
            try await owner.commitMosaicReservation(
                prepared.lease.reference,
                finalizedTransaction: .init(
                    signedFusionTransactionBytes: [0x01]
                )
            )
        }
        #expect(await journalProbe.readRecords() == committedRecords)
    }

    @Test("Chain-terminal replay remains historical and cannot reopen wallet state")
    func replayHistoricalResultsAfterChainTerminal() async throws {
        let prepared = try await makeCommittedAttempt(
            profile: .opalMainnetAlpha,
            network: .mainnet
        )
        let exactTransaction = try OpalBase.Account.MosaicExactTransaction(
            prepared.complete
        )
        let blockHash = Data(repeating: 0xc1, count: 32)
        try await prepared.candidate.journal.append(
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        try await prepared.candidate.journal.append(
            .broadcastIntent(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        )
        try await prepared.candidate.journal.append(
            .broadcastAccepted(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                transactionHash: exactTransaction.hash
            )
        )
        let observation = try #require(
            OpalBase.Account.MosaicAttemptChainObservation(
                transactionHash: exactTransaction.hash,
                presence: .present(
                    blockHash: blockHash,
                    confirmations: 6
                )
            )
        )
        try await prepared.candidate.journal.append(
            .chainObservation(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                observation: observation
            )
        )
        try await prepared.candidate.journal.append(
            .terminalDisposition(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                disposition: .chainFinalized(
                    transactionHash: exactTransaction.hash,
                    blockHash: blockHash,
                    confirmations: 6
                )
            )
        )
        let owner = try await makePrivateAlphaRecoveryOwner(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        guard case .terminal(.chainFinalized) = try await owner.resume()
        else {
            Issue.record("Expected authenticated chain terminal")
            return
        }
        let recordsBeforeReplay = await prepared.fixture.journalProbe
            .readRecords()

        let lease = try await owner.reserveMosaicContribution(
            for: prepared.fixture.reservationRequest
        )
        let finalized = try await owner.finalizeMosaicTransaction(
            for: prepared.request
        )
        try await owner.commitMosaicReservation(
            prepared.lease.reference,
            completeTransaction: prepared.complete
        )
        try await owner.commitMosaicReservation(
            prepared.lease.reference,
            finalizedTransaction: prepared.finalized
        )
        #expect(lease == prepared.lease)
        #expect(finalized == prepared.finalized)
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .terminalReservation
        ) {
            try await owner.releaseMosaicReservation(
                prepared.lease.reference
            )
        }

        let changedComplete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: [0x01]
        )
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure
                .conflictingCompleteTransaction
        ) {
            try await owner.commitMosaicReservation(
                prepared.lease.reference,
                completeTransaction: changedComplete
            )
        }
        #expect(
            await prepared.fixture.journalProbe.readRecords()
                == recordsBeforeReplay
        )
        #expect(
            !(await prepared.fixture.addressBook.listUTXOs())
                .contains(prepared.fixture.selectedInput)
        )
    }

    private func expectRecoveryBindingRejection(
        fusionIdentifierBytes: (
            attempt: UInt8?,
            generation: UInt8?,
            material: UInt8?
        ) = (nil, nil, nil),
        changesWalletIdentifier: Bool = false,
        changesWalletGeneration: Bool = false
    ) async throws {
        let prepared = try await makeReservedAttempt()
        let baseBinding = await prepared.fixture.host.attemptBinding
        let fusionBinding = try OpalFusion.MosaicPrivateAlphaRuntime.Binding(
            attemptIdentifier: fusionIdentifierBytes.attempt.map {
                Data(repeating: $0, count: 32)
            } ?? baseBinding.attemptIdentifier,
            generationIdentifier: fusionIdentifierBytes.generation.map {
                Data(repeating: $0, count: 32)
            } ?? baseBinding.generationIdentifier,
            materialIdentifier: fusionIdentifierBytes.material.map {
                Data(repeating: $0, count: 32)
            } ?? baseBinding.materialIdentifier
        )
        let fusionRecovery = try await makeFusionRecovery(
            binding: fusionBinding
        )
        let journalRecovery = OpalBase.Account.MosaicPrivateAlphaJournal
            .LoadedRecovery(
                try await prepared.fixture.journalProbe.loadRecovery()
            )
        await prepared.fixture.addressBook.releaseUTXOs(
            [prepared.fixture.selectedInput]
        )
        let recordsBefore = await prepared.fixture.journalProbe.readRecords()
        let spendableBefore = await prepared.fixture.addressBook
            .listSpendableUTXOs()
        let wrongIdentifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000099")
        )

        do {
            _ = try await OpalBase.Account.MosaicPrivateAlphaRuntime
                .loadRecoveryOwner(
                    account: prepared.fixture.account,
                    expectedWalletReservationIdentifier:
                        changesWalletIdentifier
                            ? wrongIdentifier
                            : baseBinding.walletReservationReference.identifier,
                    expectedWalletGeneration: changesWalletGeneration
                        ? baseBinding.walletReservationReference.generation + 1
                        : baseBinding.walletReservationReference.generation,
                    fusionRecovery: fusionRecovery,
                    journalRecovery: journalRecovery
                )
            Issue.record("Expected exact cross-package binding rejection")
        } catch let failure as OpalBase.Account.MosaicPrivateAlphaRuntime
            .Failure {
            #expect(failure == .invalidBinding)
        }
        #expect(
            await prepared.fixture.journalProbe.readRecords() == recordsBefore
        )
        #expect(
            await prepared.fixture.addressBook.listSpendableUTXOs()
                == spendableBefore
        )
    }

    private func makeFusionBinding(
        from binding: OpalBase.Account.MosaicAttemptBinding? = nil
    ) throws -> OpalFusion.MosaicPrivateAlphaRuntime.Binding {
        try .init(
            attemptIdentifier: binding?.attemptIdentifier
                ?? Data(repeating: 0x11, count: 32),
            generationIdentifier: binding?.generationIdentifier
                ?? Data(repeating: 0x22, count: 32),
            materialIdentifier: binding?.materialIdentifier
                ?? Data(repeating: 0x33, count: 32)
        )
    }

    private func makeFusionRecovery(
        binding: OpalFusion.MosaicPrivateAlphaRuntime.Binding
    ) async throws -> OpalFusion.MosaicPrivateAlphaRuntime.LoadedRecovery {
        let freshAttempt = try OpalFusion.MosaicPrivateAlphaRuntime
            .createFreshAttempt(
                boundTo: binding,
                discoveryEpochStartUnixSeconds: 1_800_000_000
            )
        let owner = try OpalFusion.MosaicPrivateAlphaRuntime.Owner(
            claiming: freshAttempt
        )
        guard case let .persist(transition) = try await owner.nextStep()
        else {
            throw OpalBase.Account.MosaicPrivateAlphaRuntime.Failure
                .invalidRecoveryState
        }
        return try OpalFusion.MosaicPrivateAlphaRuntime.loadRecovery(
            from: transition.replacementSnapshot,
            expectedBinding: binding
        )
    }

    private func makeReservedAttempt() async throws -> (
        fixture: MosaicHostFixture,
        lease: OpalFusion.Host.MosaicReservationLease
    ) {
        let transactionPolicy = await MosaicPolicyProbeActor()
            .makeTransactionPolicy(
                profile: .opalMainnetAlpha,
                network: .mainnet
            )
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: transactionPolicy,
            network: .mainnet,
            profile: .opalMainnetAlpha
        )
        return (fixture, try await fixture.reserve())
    }

    private func makeLocallySignedAttempt(
        journalProbe: MosaicAttemptJournalProbeActor = .init()
    ) async throws -> (
        fixture: MosaicHostFixture,
        lease: OpalFusion.Host.MosaicReservationLease,
        request: OpalFusion.Host.MosaicTransactionSigningRequest,
        finalized: OpalFusion.Host.FinalizedTransaction,
        complete: OpalFusion.Host.MosaicCompleteTransaction
    ) {
        let transactionPolicy = await MosaicPolicyProbeActor()
            .makeTransactionPolicy(
                profile: .opalMainnetAlpha,
                network: .mainnet
            )
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: transactionPolicy,
            network: .mainnet,
            profile: .opalMainnetAlpha,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalized = try await fixture.host.finalizeMosaicTransaction(
            for: request
        )
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )
        return (fixture, lease, request, finalized, complete)
    }

    private func changedReservationRequest(
        _ request: OpalFusion.Host.MosaicReservationRequest
    ) throws -> OpalFusion.Host.MosaicReservationRequest {
        try .init(
            attemptIdentifier: request.attemptIdentifier,
            networkGenesisHash: request.networkGenesisHash,
            roundIdentifier: Array(repeating: 0x77, count: 32),
            expiresAt: request.expiresAt,
            componentCount: request.componentCount,
            feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: request.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: request.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: request.requiredExcessFeeSatoshis,
            transactionProfileIdentifier:
                request.transactionProfileIdentifier
        )
    }
}
#endif
