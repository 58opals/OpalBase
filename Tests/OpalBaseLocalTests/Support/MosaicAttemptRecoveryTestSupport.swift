// MosaicAttemptRecoveryTestSupport.swift

#if os(macOS)
import OpalFusion
@testable import OpalBase

func makeCommittedAttempt(
    journalProbe: MosaicAttemptJournalProbeActor = .init()
) async throws -> (
    fixture: MosaicHostFixture,
    lease: OpalFusion.Host.MosaicReservationLease,
    request: OpalFusion.Host.MosaicTransactionSigningRequest,
    finalized: OpalFusion.Host.FinalizedTransaction,
    complete: OpalFusion.Host.MosaicCompleteTransaction,
    candidate: OpalBase.Account.MosaicCommittedBroadcastCandidate
) {
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
    try await fixture.host.commitMosaicReservation(
        lease.reference,
        completeTransaction: complete
    )
    let candidate = try await fixture.host.makeCommittedBroadcastCandidate()
    return (fixture, lease, request, finalized, complete, candidate)
}

func makeRecoveryGate(
    addressBook: OpalBase.Address.Book,
    journalProbe: MosaicAttemptJournalProbeActor
) async throws -> OpalBase.Account.MosaicAttemptRecoveryGate {
    let recovery = try await journalProbe.loadRecovery()
    return .init(addressBook: addressBook, recovery: recovery)
}

func makeRecoveryGate(
    addressBook: OpalBase.Address.Book,
    records: [OpalBase.Account.MosaicAttemptJournal.Record]
) async throws -> OpalBase.Account.MosaicAttemptRecoveryGate {
    let journalProbe = MosaicAttemptJournalProbeActor()
    let journal = try await journalProbe.makeFreshJournalForTesting()
    for record in records {
        try await journal.append(record)
    }
    return try await makeRecoveryGate(
        addressBook: addressBook,
        journalProbe: journalProbe
    )
}
#endif
