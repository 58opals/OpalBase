// AccountMosaicTransactionHostValidator+FailureSafety.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test("A network environment cannot accept another network's genesis hash")
    func rejectInconsistentNetworkGenesisHash() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let request = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: fixture.reservationRequest.attemptIdentifier,
            networkGenesisHash: OpalBase.Network.Environment.mainnet.mosaicGenesisHash,
            roundIdentifier: fixture.reservationRequest.roundIdentifier,
            expiresAt: fixture.reservationRequest.expiresAt,
            componentCount: fixture.reservationRequest.componentCount,
            feeRateSatoshisPerByte: fixture.reservationRequest.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: fixture.reservationRequest.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: fixture.reservationRequest.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: fixture.reservationRequest
                .requiredExcessFeeSatoshis,
            transactionProfileIdentifier: fixture.reservationRequest.transactionProfileIdentifier
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.invalidNetworkBinding) {
            _ = try await fixture.host.reserveMosaicContribution(for: request)
        }
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
    }

    @Test("A gap-maintenance failure permanently retires its reserved output")
    func retireOutputAfterGapMaintenanceFailure() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            reserveReceivingEntry: { addressBook, plannedEntry in
                try await addressBook.reserveMosaicReceivingEntry(
                    plannedEntry,
                    maintainingGapWith: {
                        throw MosaicPolicyFixtureFailure.rejected
                    }
                )
            }
        )
        let firstEntry = try #require(
            await fixture.addressBook.listEntries(for: .receiving).first
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reservationUnavailable) {
            _ = try await fixture.reserve()
        }

        let retiredEntry = try #require(
            await fixture.addressBook.findEntry(for: firstEntry.address)
        )
        #expect(retiredEntry.isUsed)
        #expect(!retiredEntry.isReserved)
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        let nextEntry = try await fixture.addressBook.selectNextEntry(for: .receiving)
        #expect(nextEntry.address != retiredEntry.address)
    }

    @Test("Scheduled expiry cleanup outlives a dropped host reference")
    func retainCleanupUntilScheduledExpiration() async throws {
        let expirationProbe = MosaicExpirationProbeActor()
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        var fixture: MosaicHostFixture? = try await .make(
            transactionPolicy: policy,
            sleepUntilDate: { _ in await expirationProbe.wait() }
        )
        let addressBook = try #require(fixture?.addressBook)
        let selectedInput = try #require(fixture?.selectedInput)
        let lease = try await #require(fixture).reserve()
        let output = try #require(lease.participantReservation.outputs.first)
        let outputScript = try OpalBase.Script.decode(
            lockingScript: Data(output.lockingScriptBytes)
        )
        let outputAddress = try OpalBase.Address(script: outputScript)
        weak let host = fixture?.host

        fixture = nil
        #expect(host != nil)
        await expirationProbe.release()
        for _ in 0 ..< 1_000 {
            if host == nil { break }
            try await Task.sleep(for: .milliseconds(1))
        }

        #expect(host == nil)
        #expect(await addressBook.listSpendableUTXOs().contains(selectedInput))
        let retiredEntry = try #require(await addressBook.findEntry(for: outputAddress))
        #expect(retiredEntry.isUsed)
        #expect(!retiredEntry.isReserved)
    }
}
#endif
