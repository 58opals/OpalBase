// AccountMosaicAttemptRecoveryPlannerValidator.swift

#if os(macOS)
import CryptoKit
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

@Suite("OpalBase.Account Mosaic attempt recovery planner", .tags(.unit, .wallet))
struct AccountMosaicAttemptRecoveryPlannerValidator {
    typealias Planner = OpalBase.Account.MosaicAttemptRecoveryPlanner

    @Test("Derive conservative recovery at every write-ahead boundary")
    func deriveRecoveryAtEveryBoundary() async throws {
        #expect(try Planner.plan(for: []) == .noAction)
        let prepared = try await makeCommittedAttempt()
        let records = await prepared.fixture.journalProbe.readRecords()
        #expect(records.count == 7)

        #expect(
            try Planner.plan(for: Array(records.prefix(1)))
                == .releaseBeforeSigning(prepared.lease.reference)
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(2)))
                == .releaseBeforeSigning(prepared.lease.reference)
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(3)))
                == .releaseBeforeSigning(prepared.lease.reference)
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(4)))
                == .reconcileSigningIntent(
                    reference: prepared.lease.reference,
                    request: prepared.request
                )
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(5)))
                == .reconcileLocallySignedTransaction(
                    reference: prepared.lease.reference,
                    transaction: prepared.finalized
                )
        )
        #expect(
            try Planner.plan(for: Array(records.prefix(6)))
                == .finishCommit(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete
                )
        )
        #expect(
            try Planner.plan(for: records)
                == .broadcastApprovalRequired(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete,
                    broadcastIntentPersisted: false
                )
        )
        let approvedRecords = records + [
            .broadcastApproved(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        ]
        #expect(
            try Planner.plan(for: approvedRecords)
                == .resumeApprovedBroadcast(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete,
                    broadcastIntentPersisted: false
                )
        )
        let approvedIntentRecords = approvedRecords + [
            .broadcastIntent(
                reference: prepared.lease.reference,
                transaction: prepared.complete
            )
        ]
        #expect(
            try Planner.plan(for: approvedIntentRecords)
                == .resumeApprovedBroadcast(
                    reference: prepared.lease.reference,
                    transaction: prepared.complete,
                    broadcastIntentPersisted: true
                )
        )

        #expect(throws: Planner.Error.invalidTransition) {
            _ = try Planner.plan(for: [records[0], records[4]])
        }
        #expect(throws: Planner.Error.invalidFirstRecord) {
            _ = try Planner.plan(for: [records[1]])
        }
        let otherReference = OpalFusion.Host.MosaicReservationReference(
            identifier: UUID(),
            generation: prepared.lease.reference.generation
        )
        #expect(throws: Planner.Error.reservationReferenceMismatch) {
            _ = try Planner.plan(
                for: [records[0], .releaseIntent(otherReference)]
            )
        }

        var conflictingBytes = prepared.complete.transactionBytes
        conflictingBytes[conflictingBytes.index(before: conflictingBytes.endIndex)] ^= 0x01
        let conflictingTransaction = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: conflictingBytes
        )
        #expect(throws: Planner.Error.conflictingTransaction) {
            _ = try Planner.plan(
                for: Array(records.prefix(6)) + [
                    .committed(
                        reference: prepared.lease.reference,
                        transaction: conflictingTransaction
                    )
                ]
            )
        }
        #expect(throws: Planner.Error.conflictingTransaction) {
            _ = try Planner.plan(
                for: records + [
                    .broadcastApproved(
                        reference: prepared.lease.reference,
                        transaction: conflictingTransaction
                    )
                ]
            )
        }
        #expect(throws: Planner.Error.conflictingTransaction) {
            _ = try Planner.plan(
                for: approvedRecords + [
                    .broadcastIntent(
                        reference: prepared.lease.reference,
                        transaction: conflictingTransaction
                    )
                ]
            )
        }
        let transactionHash = OpalBase.Transaction.Hash(
            naturalOrder: OpalCryptoAdapter.hash256(
                Data(conflictingTransaction.transactionBytes)
            )
        )
        #expect(throws: Planner.Error.conflictingTransaction) {
            _ = try Planner.plan(
                for: approvedIntentRecords + [
                    .broadcastAccepted(
                        reference: prepared.lease.reference,
                        transaction: conflictingTransaction,
                        transactionHash: transactionHash
                    )
                ]
            )
        }
    }

    @Test("Prepared leases require exact ordered outputs and input keys")
    func rejectContradictoryPreparedLease() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            outputAmountsSatoshis: [40_000, 50_000]
        )
        let lease = try await fixture.reserve()
        let records = await fixture.journalProbe.readRecords()
        guard case let .reservationPrepared(
            request,
            selectedInputs,
            outputAmountsSatoshis,
            preparedLease
        ) = records[1] else {
            Issue.record("Expected prepared reservation")
            return
        }

        let reversedOutputLease = try OpalFusion.Host.MosaicReservationLease(
            reference: preparedLease.reference,
            expiresAt: preparedLease.expiresAt,
            participantReservation: .init(
                inputs: preparedLease.participantReservation.inputs,
                outputs: preparedLease.participantReservation.outputs.reversed()
            )
        )
        #expect(throws: Planner.Error.invalidRecord) {
            _ = try Planner.plan(
                for: [
                    records[0],
                    .reservationPrepared(
                        request: request,
                        selectedInputs: selectedInputs,
                        outputAmountsSatoshis: outputAmountsSatoshis,
                        lease: reversedOutputLease
                    ),
                ]
            )
        }

        let duplicatedScriptOutputs = preparedLease.participantReservation
            .outputs.enumerated().map { index, output in
                OpalFusion.Host.ParticipantOutput(
                    lockingScriptBytes: preparedLease.participantReservation
                        .outputs[0].lockingScriptBytes,
                    amountSatoshis: outputAmountsSatoshis[index]
                )
            }
        let duplicatedScriptLease = try OpalFusion.Host.MosaicReservationLease(
            reference: preparedLease.reference,
            expiresAt: preparedLease.expiresAt,
            participantReservation: .init(
                inputs: preparedLease.participantReservation.inputs,
                outputs: duplicatedScriptOutputs
            )
        )
        #expect(throws: Planner.Error.invalidRecord) {
            _ = try Planner.plan(
                for: [
                    records[0],
                    .reservationPrepared(
                        request: request,
                        selectedInputs: selectedInputs,
                        outputAmountsSatoshis: outputAmountsSatoshis,
                        lease: duplicatedScriptLease
                    ),
                ]
            )
        }

        let input = try #require(
            preparedLease.participantReservation.inputs.first
        )
        let missingKeyInput = OpalFusion.Host.ParticipantInput(
            outpointTransactionHashBytes: input.outpointTransactionHashBytes,
            outpointIndex: input.outpointIndex,
            amountSatoshis: input.amountSatoshis,
            lockingScriptBytes: input.lockingScriptBytes,
            publicKey: nil
        )
        let missingKeyLease = try OpalFusion.Host.MosaicReservationLease(
            reference: preparedLease.reference,
            expiresAt: preparedLease.expiresAt,
            participantReservation: .init(
                inputs: [missingKeyInput],
                outputs: preparedLease.participantReservation.outputs
            )
        )
        let contradictoryRecords: [
            OpalBase.Account.MosaicAttemptJournal.Record
        ] = [
            records[0],
            .reservationPrepared(
                request: request,
                selectedInputs: selectedInputs,
                outputAmountsSatoshis: outputAmountsSatoshis,
                lease: missingKeyLease
            ),
        ]
        #expect(throws: Planner.Error.invalidRecord) {
            _ = try Planner.plan(for: contradictoryRecords)
        }
        let codec = try OpalBase.Account.MosaicAttemptJournalCodec(
            authenticationKey: SymmetricKey(
                data: Data(repeating: 0x71, count: 32)
            ),
            scope: .init(
                walletIdentifier: UUID(),
                journalIdentifier: UUID()
            )
        )
        let contradictoryEnvelope = try codec.seal(
            records: contradictoryRecords
        )
        #expect(
            throws: OpalBase.Account.MosaicAttemptJournalCodec.Failure
                .invalidSnapshot
        ) {
            _ = try codec.open(contradictoryEnvelope)
        }

        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Reservation records preserve outpoint and profile semantics")
    func rejectSemanticallyInvalidReservationRecords() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            outputAmountsSatoshis: [40_000, 50_000]
        )
        let lease = try await fixture.reserve()
        let records = await fixture.journalProbe.readRecords()
        guard case let .reservationPrepared(
            request,
            selectedInputs,
            outputAmountsSatoshis,
            preparedLease
        ) = records[1],
              let selectedInput = selectedInputs.first else {
            Issue.record("Expected prepared reservation")
            return
        }

        let contradictoryDuplicate = OpalBase.Account.MosaicAttemptJournal
            .SelectedInput(
                transactionHash: selectedInput.transactionHash,
                outputIndex: selectedInput.outputIndex,
                amountSatoshis: selectedInput.amountSatoshis + 1,
                lockingScript: selectedInput.lockingScript
            )
        #expect(throws: Planner.Error.invalidRecord) {
            _ = try Planner.plan(
                for: [
                    records[0],
                    .reservationIntent(
                        reference: preparedLease.reference,
                        request: request,
                        selectedInputs: [
                            selectedInput,
                            contradictoryDuplicate,
                        ],
                        outputAmountsSatoshis: outputAmountsSatoshis
                    ),
                ]
            )
        }

        let wrongComponentCountRequest = try OpalFusion.Host
            .MosaicReservationRequest(
                attemptIdentifier: request.attemptIdentifier,
                networkGenesisHash: request.networkGenesisHash,
                roundIdentifier: request.roundIdentifier,
                expiresAt: request.expiresAt,
                componentCount: request.componentCount - 1,
                feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis:
                    request.minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis:
                    request.maximumExcessFeeSatoshis,
                requiredExcessFeeSatoshis:
                    request.requiredExcessFeeSatoshis,
                transactionProfileIdentifier:
                    request.transactionProfileIdentifier
            )
        #expect(throws: Planner.Error.invalidRecord) {
            _ = try Planner.plan(
                for: [
                    records[0],
                    .reservationPrepared(
                        request: wrongComponentCountRequest,
                        selectedInputs: selectedInputs,
                        outputAmountsSatoshis: outputAmountsSatoshis,
                        lease: preparedLease
                    ),
                ]
            )
        }
        try await fixture.host.releaseMosaicReservation(lease.reference)

        let mainnetPolicy = OpalBase.Account.MosaicTransactionPolicy(
            profile: .opalMainnetAlpha,
            network: .mainnet
        ) { _, _, _ in }
        let mainnetFixture = try await MosaicHostFixture.make(
            transactionPolicy: mainnetPolicy,
            network: .mainnet,
            profile: .opalMainnetAlpha
        )
        let mainnetLease = try await mainnetFixture.reserve()
        let mainnetRecords = await mainnetFixture.journalProbe.readRecords()
        guard case let .reservationPrepared(
            mainnetRequest,
            mainnetInputs,
            mainnetAmounts,
            recordedMainnetLease
        ) = mainnetRecords[1],
              let originalOutput = recordedMainnetLease
                .participantReservation.outputs.first,
              let originalAmount = mainnetAmounts.first,
              originalAmount > 1 else {
            Issue.record("Expected mainnet prepared reservation")
            return
        }
        let invalidAmount = originalAmount - 1
        let invalidContributionLease = try OpalFusion.Host
            .MosaicReservationLease(
                reference: recordedMainnetLease.reference,
                expiresAt: recordedMainnetLease.expiresAt,
                participantReservation: .init(
                    inputs: recordedMainnetLease.participantReservation.inputs,
                    outputs: [
                        .init(
                            lockingScriptBytes:
                                originalOutput.lockingScriptBytes,
                            amountSatoshis: invalidAmount
                        ),
                    ]
                )
            )
        #expect(throws: Planner.Error.invalidRecord) {
            _ = try Planner.plan(
                for: [
                    mainnetRecords[0],
                    .reservationPrepared(
                        request: mainnetRequest,
                        selectedInputs: mainnetInputs,
                        outputAmountsSatoshis: [invalidAmount],
                        lease: invalidContributionLease
                    ),
                ]
            )
        }
        try await mainnetFixture.host.releaseMosaicReservation(
            mainnetLease.reference
        )
    }

    @Test("A failed terminal release write yields an exact recovery plan")
    func recoverReleaseAfterTerminalPersistenceFailure() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(failingAppendIndices: [3])
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        let records = await journalProbe.readRecords()
        #expect(records.count == 4)
        #expect(try Planner.plan(for: records) == .finishRelease(lease.reference))
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
    }

    @Test("A pre-sign release is terminal and idempotently recoverable")
    func recoverReleasedAttempt() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let lease = try await fixture.reserve()
        try await fixture.host.releaseMosaicReservation(lease.reference)

        let records = await fixture.journalProbe.readRecords()
        #expect(records.count == 5)
        #expect(try Planner.plan(for: records) == .released)
    }

    @Test("A failed locally-signed journal write quarantines inputs without resigning")
    func quarantineAfterLocallySignedPersistenceFailure() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(
            failingAppendIndices: [3]
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            _ = try await fixture.host.finalizeMosaicTransaction(for: request)
        }
        #expect(await fixture.host.readSigningInvocationCount() == 1)
        await #expect(throws: OpalBase.Account.MosaicHostFailure.reconciliationRequired) {
            try await fixture.host.releaseMosaicReservation(lease.reference)
        }
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .reconcileSigningIntent(
                    reference: lease.reference,
                    request: request
                )
        )

        let finalized = try await fixture.host.finalizeMosaicTransaction(for: request)
        #expect(await fixture.host.readSigningInvocationCount() == 1)
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .reconcileLocallySignedTransaction(
                    reference: lease.reference,
                    transaction: finalized
                )
        )
    }

    @Test("Retry an exact commit after its terminal journal write fails")
    func retryCommitPersistenceExactly() async throws {
        let journalProbe = MosaicAttemptJournalProbeActor(
            failingAppendIndices: [5]
        )
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            journalProbe: journalProbe
        )
        let lease = try await fixture.reserve()
        let request = try fixture.makeSigningRequest(lease: lease)
        let finalized = try await fixture.host.finalizeMosaicTransaction(for: request)
        let complete = try OpalFusion.Host.MosaicCompleteTransaction(
            transactionBytes: finalized.signedFusionTransactionBytes
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.journalPersistenceFailed) {
            try await fixture.host.commitMosaicReservation(
                lease.reference,
                completeTransaction: complete
            )
        }
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .finishCommit(reference: lease.reference, transaction: complete)
        )

        try await fixture.host.commitMosaicReservation(
            lease.reference,
            completeTransaction: complete
        )
        #expect(
            try Planner.plan(for: await journalProbe.readRecords())
                == .broadcastApprovalRequired(
                    reference: lease.reference,
                    transaction: complete,
                    broadcastIntentPersisted: false
                )
        )
    }
}
#endif
