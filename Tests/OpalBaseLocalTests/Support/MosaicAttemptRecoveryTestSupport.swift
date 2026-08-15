// MosaicAttemptRecoveryTestSupport.swift

#if os(macOS)
import OpalFusion
@testable import OpalBase

func makeCommittedAttempt(
    journalProbe: MosaicAttemptJournalProbeActor = .init(),
    profile: OpalFusion.Mosaic.Profile = .opalV0,
    network: OpalBase.Network.Environment = .chipnet
) async throws -> (
    fixture: MosaicHostFixture,
    lease: OpalFusion.Host.MosaicReservationLease,
    request: OpalFusion.Host.MosaicTransactionSigningRequest,
    finalized: OpalFusion.Host.FinalizedTransaction,
    complete: OpalFusion.Host.MosaicCompleteTransaction,
    candidate: OpalBase.Account.MosaicCommittedBroadcastCandidate
) {
    let policy = await MosaicPolicyProbeActor().makeTransactionPolicy(
        profile: profile,
        network: network
    )
    let fixture = try await MosaicHostFixture.make(
        transactionPolicy: policy,
        network: network,
        profile: profile,
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

func makePrivateAlphaRecoveryOwner(
    addressBook: OpalBase.Address.Book,
    journalProbe: MosaicAttemptJournalProbeActor
) async throws -> OpalBase.Account.MosaicPrivateAlphaRecoveryOwner {
    let recovery = try await journalProbe.loadRecovery()
    return try .init(
        addressBook: addressBook,
        recovery: recovery
    )
}
#endif
