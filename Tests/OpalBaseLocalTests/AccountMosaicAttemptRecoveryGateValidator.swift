// AccountMosaicAttemptRecoveryGateValidator.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account Mosaic attempt recovery gate", .tags(.unit, .wallet))
struct AccountMosaicAttemptRecoveryGateValidator {
    @Test("Startup recovery re-quarantines exact journaled inputs")
    func quarantineRestoredInputsBeforeRecoveryAction() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        #expect(
            await prepared.fixture.addressBook.listSpendableUTXOs()
                .contains(prepared.fixture.selectedInput)
        )

        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: prepared.fixture.journalProbe
        )
        let candidateOutcome = try await gate.restoreInputQuarantineAndPlan()
        guard case let .broadcastApprovalRequired(candidate) = candidateOutcome else {
            Issue.record("Expected a broadcast-approval candidate")
            return
        }
        #expect(candidate.reservationRequest == prepared.fixture.reservationRequest)
        #expect(candidate.reservationReference == prepared.lease.reference)
        #expect(candidate.completeTransaction == prepared.complete)
        #expect(!candidate.approvalPersisted)
        #expect(!candidate.broadcastIntentPersisted)
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(prepared.fixture.selectedInput)
        )

        await prepared.fixture.addressBook.releaseUTXOs(
            Set([prepared.fixture.selectedInput])
        )
        let signingGate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            records: Array(records.prefix(3))
        )
        let signingOutcome = try await signingGate.restoreInputQuarantineAndPlan()
        guard case let .walletReconciliationRequired(signingPlan)
                = signingOutcome else {
            Issue.record("Expected signing reconciliation")
            return
        }
        #expect(
            signingPlan == .reconcileSigningIntent(
                reference: prepared.lease.reference,
                request: prepared.request
            )
        )
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(prepared.fixture.selectedInput)
        )
    }

    @Test("Recovery blocks missing inputs and rejects payload substitution")
    func validateRecoveredSelectedInputPayload() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            records: records
        )

        let missingInputOutcome = try await gate.restoreInputQuarantineAndPlan()
        guard case let .walletReconciliationRequired(missingInputPlan)
                = missingInputOutcome else {
            Issue.record("Expected missing-input reconciliation")
            return
        }
        #expect(
            missingInputPlan == .broadcastApprovalRequired(
                reference: prepared.lease.reference,
                transaction: prepared.complete,
                broadcastIntentPersisted: false
            )
        )

        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let substitutedInput = OpalBase.Transaction.Output.Unspent(
            value: prepared.fixture.selectedInput.value + 1,
            lockingScript: prepared.fixture.selectedInput.lockingScript,
            previousTransactionHash:
                prepared.fixture.selectedInput.previousTransactionHash,
            previousTransactionOutputIndex:
                prepared.fixture.selectedInput.previousTransactionOutputIndex
        )
        guard case let .reservationIntent(
            reference,
            request,
            _,
            outputAmountsSatoshis
        ) = records[0] else {
            Issue.record("Expected reservation intent")
            return
        }
        var substitutedRecords = records
        substitutedRecords[0] = .reservationIntent(
            reference: reference,
            request: request,
            selectedInputs: [.init(substitutedInput)],
            outputAmountsSatoshis: outputAmountsSatoshis
        )
        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .selectedInputMismatch
        ) {
            let substitutedGate = try await makeRecoveryGate(
                addressBook: prepared.fixture.addressBook,
                records: substitutedRecords
            )
            _ = try await substitutedGate.restoreInputQuarantineAndPlan()
        }
    }

    @Test("Recovery rejects invalid journals, inputs, and broadcast candidates")
    func rejectInvalidRecoveryAuthority() async throws {
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .invalidJournal(.invalidTransition)
        ) {
            _ = try await makeRecoveryGate(
                addressBook: prepared.fixture.addressBook,
                records: [records[0], records[4]]
            )
        }

        guard case let .reservationIntent(
            reference,
            request,
            selectedInputs,
            outputAmountsSatoshis
        ) = records[0] else {
            Issue.record("Expected reservation intent")
            return
        }
        var duplicateInputRecords = records
        duplicateInputRecords[0] = .reservationIntent(
            reference: reference,
            request: request,
            selectedInputs: selectedInputs + selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis
        )
        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .invalidSelectedInput
        ) {
            let duplicateInputGate = try await makeRecoveryGate(
                addressBook: prepared.fixture.addressBook,
                records: duplicateInputRecords
            )
            _ = try await duplicateInputGate.restoreInputQuarantineAndPlan()
        }

        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let futureVersionRequest = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: request.attemptIdentifier,
            networkGenesisHash: request.networkGenesisHash,
            roundIdentifier: request.roundIdentifier,
            expiresAt: request.expiresAt,
            componentCount: request.componentCount,
            feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: request.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: request.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: request.requiredExcessFeeSatoshis,
            transactionProfileIdentifier:
                "bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.5"
        )
        var futureVersionRecords = records
        futureVersionRecords[0] = .reservationIntent(
            reference: reference,
            request: futureVersionRequest,
            selectedInputs: selectedInputs,
            outputAmountsSatoshis: outputAmountsSatoshis
        )
        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .invalidBroadcastCandidate
        ) {
            let futureVersionGate = try await makeRecoveryGate(
                addressBook: prepared.fixture.addressBook,
                records: futureVersionRecords
            )
            _ = try await futureVersionGate.restoreInputQuarantineAndPlan()
        }
        #expect(
            !(await prepared.fixture.addressBook.listSpendableUTXOs())
                .contains(prepared.fixture.selectedInput)
        )
    }

    @Test("Terminal release and empty recovery do not quarantine spendable inputs")
    func leaveTerminalOrUnstartedWalletStateUntouched() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .creationUncertain
        ) {
            _ = try await fixture.journalProbe.loadRecovery()
        }
        #expect(
            await fixture.addressBook.listSpendableUTXOs()
                .contains(fixture.selectedInput)
        )

        let lease = try await fixture.reserve()
        try await fixture.host.releaseMosaicReservation(lease.reference)
        let releasedGate = try await makeRecoveryGate(
            addressBook: fixture.addressBook,
            journalProbe: fixture.journalProbe
        )
        let releasedOutcome = try await releasedGate
            .restoreInputQuarantineAndPlan()
        guard case .released = releasedOutcome else {
            Issue.record("Expected terminal release recovery")
            return
        }
        #expect(
            await fixture.addressBook.listSpendableUTXOs()
                .contains(fixture.selectedInput)
        )
    }

    @Test("Restarted recovery cannot repeat wallet or network effects")
    func recoverAuthenticatedSnapshotWithoutDuplicateEffects() async throws {
        let prepared = try await makeCommittedAttempt()
        let recordsBeforeRecovery = await prepared.fixture.journalProbe
            .readRecords()
        let envelopeBeforeRecovery = try #require(
            await prepared.fixture.journalProbe.readPersistedEnvelope()
        )
        #expect(await prepared.fixture.host.readSigningInvocationCount() == 1)

        await prepared.fixture.addressBook.addUTXO(prepared.fixture.selectedInput)
        let restartedJournalProbe = try await prepared.fixture.journalProbe
            .makeRestartedProbe()
        let gate = try await makeRecoveryGate(
            addressBook: prepared.fixture.addressBook,
            journalProbe: restartedJournalProbe
        )
        let outcome = try await gate.restoreInputQuarantineAndPlan()
        guard case .broadcastApprovalRequired = outcome else {
            Issue.record("Expected an authenticated committed recovery boundary")
            return
        }

        #expect(await prepared.fixture.host.readSigningInvocationCount() == 1)
        #expect(
            await restartedJournalProbe.readRecords()
                == recordsBeforeRecovery
        )
        #expect(
            await restartedJournalProbe.readPersistedEnvelope()
                == envelopeBeforeRecovery
        )
        await #expect(
            throws: OpalBase.Account.MosaicAttemptRecoveryGate.Failure
                .outcomeAlreadyIssued
        ) {
            _ = try await gate.restoreInputQuarantineAndPlan()
        }
        await #expect(
            throws: OpalBase.Account.MosaicAttemptJournalStore.Failure
                .alreadyExists
        ) {
            _ = try await restartedJournalProbe
                .makeFreshJournalForTesting()
        }
    }
}
#endif
