// AccountMosaicTransactionHostValidator+Reservation.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

extension AccountMosaicTransactionHostValidator {
    @Test("Reject unsupported profile-network pairs and malformed contributions")
    func rejectUnsupportedBindingsAndMalformedContributions() async throws {
        let account = try await AccountTestFixtures.makeAccount()
        let input = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            usage: .change,
            hashByte: 0xb1
        )
        let addressBook = await account.addressBook
        let journalProbe = MosaicAttemptJournalProbeActor()
        let mismatchedPolicyBindings: [
            (
                hostProfile: OpalFusion.Mosaic.Profile,
                hostNetwork: OpalBase.Network.Environment,
                policyProfile: OpalFusion.Mosaic.Profile,
                policyNetwork: OpalBase.Network.Environment
            )
        ] = [
            (.opalV0, .chipnet, .opalMainnetAlpha, .chipnet),
            (.opalV0, .chipnet, .opalV0, .mainnet)
        ]
        for binding in mismatchedPolicyBindings {
            let policy = OpalBase.Account.MosaicTransactionPolicy(
                profile: binding.policyProfile,
                network: binding.policyNetwork
            ) { _, _, _ in }
            #expect(
                throws: OpalBase.Account.MosaicHostFailure
                    .invalidProfileNetworkBinding
            ) {
                _ = try OpalBase.Account.MosaicTransactionHostActor(
                    addressBook: addressBook,
                    profile: binding.hostProfile,
                    network: binding.hostNetwork,
                    generation: 1,
                    selectedInputs: [input],
                    outputAmountsSatoshis: [90_000],
                    transactionPolicy: policy,
                    attemptJournal: journalProbe.makeJournal()
                )
            }
        }
        let unsupportedPairs: [
            (OpalFusion.Mosaic.Profile, OpalBase.Network.Environment)
        ] = [
            (.draft1, .chipnet),
            (.opalV0, .mainnet),
            (.opalV0, .testnet),
            (.opalMainnetAlpha, .chipnet),
            (.opalMainnetAlpha, .testnet)
        ]
        for (profile, network) in unsupportedPairs {
            let policy = OpalBase.Account.MosaicTransactionPolicy(
                profile: profile,
                network: network
            ) { _, _, _ in }
            #expect(
                throws: OpalBase.Account.MosaicHostFailure
                    .invalidProfileNetworkBinding
            ) {
                _ = try OpalBase.Account.MosaicTransactionHostActor(
                    addressBook: addressBook,
                    profile: profile,
                    network: network,
                    generation: 1,
                    selectedInputs: [input],
                    outputAmountsSatoshis: [90_000],
                    transactionPolicy: policy,
                    attemptJournal: .init { _ in }
                )
            }
        }

        let policy = await MosaicPolicyProbeActor().transactionPolicy
        #expect(throws: OpalBase.Account.MosaicHostFailure.invalidContributionPolicy) {
            _ = try OpalBase.Account.MosaicTransactionHostActor(
                addressBook: addressBook,
                profile: .opalV0,
                network: .chipnet,
                generation: 1,
                selectedInputs: [],
                outputAmountsSatoshis: [90_000],
                transactionPolicy: policy,
                attemptJournal: .init { _ in }
            )
        }
        #expect(await journalProbe.readRecords().isEmpty)
        #expect(await addressBook.listSpendableUTXOs().contains(input))
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

    @Test("Profile-incompatible reservation terms fail before wallet mutation")
    func rejectProfileIncompatibleReservationTerms() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let valid = fixture.reservationRequest
        let invalidRequests = [
            try OpalFusion.Host.MosaicReservationRequest(
                attemptIdentifier: valid.attemptIdentifier,
                networkGenesisHash: valid.networkGenesisHash,
                roundIdentifier: valid.roundIdentifier,
                expiresAt: valid.expiresAt,
                componentCount: valid.componentCount - 1,
                feeRateSatoshisPerByte: valid.feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: valid.minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: valid.maximumExcessFeeSatoshis,
                transactionProfileIdentifier: valid.transactionProfileIdentifier
            ),
            try OpalFusion.Host.MosaicReservationRequest(
                attemptIdentifier: valid.attemptIdentifier,
                networkGenesisHash: valid.networkGenesisHash,
                roundIdentifier: valid.roundIdentifier,
                expiresAt: valid.expiresAt,
                componentCount: valid.componentCount,
                feeRateSatoshisPerByte: 2,
                minimumExcessFeeSatoshis: valid.minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: valid.maximumExcessFeeSatoshis,
                transactionProfileIdentifier: valid.transactionProfileIdentifier
            ),
            try OpalFusion.Host.MosaicReservationRequest(
                attemptIdentifier: valid.attemptIdentifier,
                networkGenesisHash: valid.networkGenesisHash,
                roundIdentifier: valid.roundIdentifier,
                expiresAt: valid.expiresAt,
                componentCount: valid.componentCount,
                feeRateSatoshisPerByte: valid.feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: 1,
                maximumExcessFeeSatoshis: 1,
                transactionProfileIdentifier: valid.transactionProfileIdentifier
            ),
            try OpalFusion.Host.MosaicReservationRequest(
                attemptIdentifier: valid.attemptIdentifier,
                networkGenesisHash: valid.networkGenesisHash,
                roundIdentifier: valid.roundIdentifier,
                expiresAt: valid.expiresAt,
                componentCount: valid.componentCount,
                feeRateSatoshisPerByte: valid.feeRateSatoshisPerByte,
                minimumExcessFeeSatoshis: valid.minimumExcessFeeSatoshis,
                maximumExcessFeeSatoshis: valid.maximumExcessFeeSatoshis,
                transactionProfileIdentifier: OpalFusion.Mosaic.Profile.draft1
                    .transactionProfileIdentifier
            )
        ]

        for request in invalidRequests {
            await #expect(
                throws: OpalBase.Account.MosaicHostFailure.invalidReservationProfile
            ) {
                _ = try await fixture.host.reserveMosaicContribution(for: request)
            }
        }
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        #expect(await fixture.journalProbe.readRecords().isEmpty)

        let lease = try await fixture.reserve()
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("A failed Mosaic reserve cannot clear another UTXO reservation")
    func preservePreexistingInputReservation() async throws {
        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let fixture = try await MosaicHostFixture.make(transactionPolicy: policy)
        let selectedInputs = Set([fixture.selectedInput])
        try await fixture.addressBook.reserveUTXOs(
            selectedInputs,
            tokenSelectionPolicy: .excludeTokenUTXOs
        )

        await #expect(throws: OpalBase.Account.MosaicHostFailure.reservationUnavailable) {
            _ = try await fixture.reserve()
        }
        #expect(
            !(await fixture.addressBook.listSpendableUTXOs()).contains(fixture.selectedInput)
        )

        await fixture.addressBook.releaseUTXOs(selectedInputs)
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
