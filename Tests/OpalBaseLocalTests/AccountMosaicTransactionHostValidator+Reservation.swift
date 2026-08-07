// AccountMosaicTransactionHostValidator+Reservation.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test("Mainnet and malformed contribution policies remain unavailable")
    func rejectMainnetAndMalformedContributionPolicies() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let input = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            usage: .change,
            hashByte: 0xb1
        )
        let addressBook = await account.addressBook
        let policy = await MosaicPolicyProbeActor().transactionPolicy

        #expect(throws: OpalBase.Account.MosaicHostFailure.mainnetUnavailable) {
            _ = try OpalBase.Account.MosaicTransactionHostActor(
                addressBook: addressBook,
                network: .mainnet,
                generation: 1,
                selectedInputs: [input],
                outputAmountsSatoshis: [90_000],
                transactionPolicy: policy,
                attemptJournal: .init { _ in }
            )
        }
        #expect(throws: OpalBase.Account.MosaicHostFailure.invalidContributionPolicy) {
            _ = try OpalBase.Account.MosaicTransactionHostActor(
                addressBook: addressBook,
                network: .chipnet,
                generation: 1,
                selectedInputs: [],
                outputAmountsSatoshis: [90_000],
                transactionPolicy: policy,
                attemptJournal: .init { _ in }
            )
        }
    }

    @Test("Wallet material remains unreserved until the manifest-bound callback")
    func delayWalletMutationUntilReservation() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let firstReceivingEntry = try #require(
            await fixture.addressBook.listEntries(for: .receiving).first
        )

        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        #expect(!firstReceivingEntry.isReserved)
        #expect(!firstReceivingEntry.isUsed)

        let lease = try await fixture.reserve()
        let duplicateLease = try await fixture.reserve()

        #expect(duplicateLease == lease)
        #expect(!(await fixture.addressBook.listSpendableUTXOs()).contains(fixture.selectedInput))
        #expect(
            lease.participantReservation.outputs.first?.lockingScriptBytes
                == [UInt8](firstReceivingEntry.address.lockingScript.data)
        )
        #expect(await fixture.host.readSigningInvocationCount() == 0)
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Component overflow fails without reserving wallet material")
    func rejectComponentOverflowBeforeReservation() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let request = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: fixture.reservationRequest.attemptIdentifier,
            networkGenesisHash: fixture.reservationRequest.networkGenesisHash,
            roundIdentifier: fixture.reservationRequest.roundIdentifier,
            expiresAt: fixture.reservationRequest.expiresAt,
            componentCount: 1,
            feeRateSatoshisPerByte: fixture.reservationRequest.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: fixture.reservationRequest.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: fixture.reservationRequest.maximumExcessFeeSatoshis,
            transactionProfileIdentifier: fixture.reservationRequest.transactionProfileIdentifier
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidContributionPolicy) {
            _ = try await fixture.host.reserveMosaicContribution(for: request)
        }
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
    }

    @Test("In-place retry and stale generations cannot affect an active lease")
    func rejectInPlaceRetryAndStaleGeneration() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let lease = try await fixture.reserve()
        let replacementRequest = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: [0x12],
            networkGenesisHash: fixture.reservationRequest.networkGenesisHash,
            roundIdentifier: Array(repeating: 0x34, count: 32),
            expiresAt: fixture.reservationRequest.expiresAt,
            componentCount: fixture.reservationRequest.componentCount,
            feeRateSatoshisPerByte: fixture.reservationRequest.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: fixture.reservationRequest.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: fixture.reservationRequest.maximumExcessFeeSatoshis,
            transactionProfileIdentifier: fixture.reservationRequest.transactionProfileIdentifier
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.inPlaceRetryNotPermitted) {
            _ = try await fixture.host.reserveMosaicContribution(for: replacementRequest)
        }
        let staleReference = OpalFusion.Host.MosaicReservationReference(
            identifier: lease.reference.identifier,
            generation: lease.reference.generation + 1
        )
        await #expect(throws: OpalBase.Account.MosaicHostFailure.staleReservationReference) {
            try await fixture.host.releaseMosaicReservation(staleReference)
        }
        #expect(!(await fixture.addressBook.listSpendableUTXOs()).contains(fixture.selectedInput))
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Release is idempotent and permanently retires fresh outputs")
    func releaseIdempotentlyAndRetireFreshOutputs() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let lease = try await fixture.reserve()
        let output = try #require(lease.participantReservation.outputs.first)
        let outputScript = try OpalBase.Script.decode(
            lockingScript: Data(output.lockingScriptBytes)
        )
        let outputAddress = try OpalBase.Address(script: outputScript)

        try await fixture.host.releaseMosaicReservation(lease.reference)
        try await fixture.host.releaseMosaicReservation(lease.reference)

        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        let retiredEntry = try #require(await fixture.addressBook.findEntry(for: outputAddress))
        #expect(retiredEntry.isUsed)
        #expect(!retiredEntry.isReserved)
        let nextEntry = try await fixture.addressBook.selectNextEntry(for: .receiving)
        #expect(nextEntry.address != retiredEntry.address)
    }

    @Test("Expiration releases inputs and retires fresh outputs")
    func expireReservationConservatively() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let lease = try await fixture.reserve()

        try await fixture.host.expireMosaicReservation(
            lease.reference,
            at: lease.expiresAt
        )

        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        await #expect(throws: OpalBase.Account.MosaicHostFailure.terminalReservation) {
            _ = try await fixture.host.finalizeMosaicTransaction(
                for: fixture.makeSigningRequest(lease: lease)
            )
        }
    }
}
#endif
