// AccountMosaicTransactionHostValidator+Reservation.swift

#if os(macOS)
import Foundation
import OpalCrypto
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
            let journalProbe = MosaicAttemptJournalProbeActor()
            let attemptJournal = try await journalProbe
                .makeFreshJournalForTesting()
            let policy = OpalBase.Account.MosaicTransactionPolicy(
                profile: binding.policyProfile,
                network: binding.policyNetwork
            ) { _, _, _ in }
            do {
                _ = try OpalBase.Account.MosaicTransactionHostActor(
                    addressBook: addressBook,
                    profile: binding.hostProfile,
                    network: binding.hostNetwork,
                    attemptBinding: try #require(
                        MosaicHostFixture.makeAttemptBinding(
                            walletGeneration: 1
                        )
                    ),
                    selectedInputs: [input],
                    outputAmountsSatoshis: [90_000],
                    transactionPolicy: policy,
                    attemptJournal: attemptJournal
                )
                Issue.record("Expected invalid profile-network binding")
            } catch let failure as OpalBase.Account.MosaicHostFailure {
                #expect(failure == .invalidProfileNetworkBinding)
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
            let journalProbe = MosaicAttemptJournalProbeActor()
            let attemptJournal = try await journalProbe
                .makeFreshJournalForTesting()
            let policy = OpalBase.Account.MosaicTransactionPolicy(
                profile: profile,
                network: network
            ) { _, _, _ in }
            do {
                _ = try OpalBase.Account.MosaicTransactionHostActor(
                    addressBook: addressBook,
                    profile: profile,
                    network: network,
                    attemptBinding: try #require(
                        MosaicHostFixture.makeAttemptBinding(
                            walletGeneration: 1
                        )
                    ),
                    selectedInputs: [input],
                    outputAmountsSatoshis: [90_000],
                    transactionPolicy: policy,
                    attemptJournal: attemptJournal
                )
                Issue.record("Expected unsupported profile-network binding")
            } catch let failure as OpalBase.Account.MosaicHostFailure {
                #expect(failure == .invalidProfileNetworkBinding)
            }
        }

        let policy = await MosaicPolicyProbeActor().transactionPolicy
        let malformedJournalProbe = MosaicAttemptJournalProbeActor()
        let malformedAttemptJournal = try await malformedJournalProbe
            .makeFreshJournalForTesting()
        do {
            _ = try OpalBase.Account.MosaicTransactionHostActor(
                addressBook: addressBook,
                profile: .opalV0,
                network: .chipnet,
                attemptBinding: try #require(
                    MosaicHostFixture.makeAttemptBinding(
                        walletGeneration: 1
                    )
                ),
                selectedInputs: [],
                outputAmountsSatoshis: [90_000],
                transactionPolicy: policy,
                attemptJournal: malformedAttemptJournal
            )
            Issue.record("Expected malformed contribution rejection")
        } catch let failure as OpalBase.Account.MosaicHostFailure {
            #expect(failure == .invalidContributionPolicy)
        }
        #expect(await malformedJournalProbe.readRecords().isEmpty)
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

    @Test("Prepared outputs exceed a custom small receiving gap exactly")
    func prepareMultipleOutputsBeyondSmallGap() async throws {
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: AccountTestFixtures.makeMnemonic().deriveSeed()
        )
        let account = try OpalBase.Key.DerivationPath.Account(
            rawIndexInteger: 0
        )
        let addressBook = try await OpalBase.Address.Book(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: .bip44,
            coinType: .bitcoinCash,
            account: account,
            gapLimit: 1
        )

        let entries = try await addressBook.prepareMosaicReceivingEntries(
            count: 3
        )

        #expect(entries.count == 3)
        #expect(Set(entries.map(\.address)).count == 3)
        #expect(entries.allSatisfy { !$0.isUsed && !$0.isReserved })
        #expect(await addressBook.countEntries(for: .receiving) == 3)
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
                requiredExcessFeeSatoshis: valid.requiredExcessFeeSatoshis,
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
                requiredExcessFeeSatoshis: valid.requiredExcessFeeSatoshis,
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
                requiredExcessFeeSatoshis: 1,
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
                requiredExcessFeeSatoshis: valid.requiredExcessFeeSatoshis,
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
        #expect(await fixture.journalProbe.readRecords().count == 1)

        let lease = try await fixture.reserve()
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Mainnet alpha fee shares and local value equation fail before mutation")
    func rejectInvalidMainnetAlphaContributionTerms() async throws {
        let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        let network = OpalBase.Network.Environment.mainnet
        let policy = OpalBase.Account.MosaicTransactionPolicy(
            profile: profile,
            network: network
        ) { _, _, _ in }
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            network: network,
            profile: profile
        )
        let valid = fixture.reservationRequest
        let firstReceivingEntry = try #require(
            await fixture.addressBook.listEntries(for: .receiving).first
        )
        let zeroShare = try makeReservationRequest(
            replacing: valid,
            minimumExcessFeeSatoshis: 0,
            maximumExcessFeeSatoshis: 2,
            requiredExcessFeeSatoshis: 0
        )
        let excessiveShare = try makeReservationRequest(
            replacing: valid,
            minimumExcessFeeSatoshis: 1,
            maximumExcessFeeSatoshis: 3,
            requiredExcessFeeSatoshis: 3
        )
        let legacyAlpha3Profile = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: valid.attemptIdentifier,
            networkGenesisHash: valid.networkGenesisHash,
            roundIdentifier: valid.roundIdentifier,
            expiresAt: valid.expiresAt,
            componentCount: valid.componentCount,
            feeRateSatoshisPerByte: valid.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: valid.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: valid.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: valid.requiredExcessFeeSatoshis,
            transactionProfileIdentifier:
                "bch-mainnet-p2pkh-schnorr/0-opal-mainnet-alpha.3"
        )

        for request in [zeroShare, excessiveShare, legacyAlpha3Profile] {
            await #expect(
                throws: OpalBase.Account.MosaicHostFailure.invalidReservationProfile
            ) {
                _ = try await fixture.host.reserveMosaicContribution(for: request)
            }
        }

        let substitutedShare = try makeReservationRequest(
            replacing: valid,
            minimumExcessFeeSatoshis: 1,
            maximumExcessFeeSatoshis: 2,
            requiredExcessFeeSatoshis: 1
        )
        await #expect(
            throws: OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
        ) {
            _ = try await fixture.host.reserveMosaicContribution(for: substitutedShare)
        }

        #expect(await fixture.journalProbe.readRecords().count == 1)
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
        let unchangedReceivingEntry = try #require(
            await fixture.addressBook.findEntry(for: firstReceivingEntry.address)
        )
        #expect(!unchangedReceivingEntry.isReserved)
        #expect(!unchangedReceivingEntry.isUsed)

        let lease = try await fixture.reserve()
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test(
        "Mainnet alpha accepts both valid contribution shares",
        arguments: [UInt64(1), UInt64(2)]
    )
    func acceptMainnetAlphaContributionShare(_ requiredShare: UInt64) async throws {
        let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        let network = OpalBase.Network.Environment.mainnet
        let policy = OpalBase.Account.MosaicTransactionPolicy(
            profile: profile,
            network: network
        ) { _, _, _ in }
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            network: network,
            profile: profile,
            requiredExcessFeeSatoshis: requiredShare
        )

        let lease = try await fixture.reserve()

        #expect(fixture.reservationRequest.requiredExcessFeeSatoshis == requiredShare)
        #expect(lease.participantReservation.outputs.first?.amountSatoshis == 99_825 - requiredShare)
        try await fixture.host.releaseMosaicReservation(lease.reference)
    }

    @Test("Mainnet alpha rejects an off-by-one local contribution")
    func rejectMainnetAlphaContributionValueMismatch() async throws {
        let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        let network = OpalBase.Network.Environment.mainnet
        let policy = OpalBase.Account.MosaicTransactionPolicy(
            profile: profile,
            network: network
        ) { _, _, _ in }
        let fixture = try await MosaicHostFixture.make(
            transactionPolicy: policy,
            network: network,
            profile: profile,
            requiredExcessFeeSatoshis: 2,
            outputAmountsSatoshis: [99_824]
        )

        await #expect(
            throws: OpalBase.Account.MosaicHostFailure.invalidContributionPolicy
        ) {
            _ = try await fixture.reserve()
        }
        #expect(await fixture.journalProbe.readRecords().count == 1)
        #expect(await fixture.addressBook.listSpendableUTXOs().contains(fixture.selectedInput))
    }

    @Test("Mainnet alpha contribution arithmetic rejects overflow before host creation")
    func rejectMainnetAlphaContributionOverflow() async throws {
        let profile = OpalFusion.Mosaic.Profile.opalMainnetAlpha
        let network = OpalBase.Network.Environment.mainnet
        let account = try await AccountTestFixtures.makeAccount()
        let firstInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: UInt64.max,
            usage: .change,
            hashByte: 0xb3
        )
        let secondInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 1,
            usage: .change,
            hashByte: 0xb4
        )
        let addressBook = await account.addressBook
        let journalProbe = MosaicAttemptJournalProbeActor()
        let attemptJournal = try await journalProbe
            .makeFreshJournalForTesting()
        let policy = OpalBase.Account.MosaicTransactionPolicy(
            profile: profile,
            network: network
        ) { _, _, _ in }

        do {
            _ = try OpalBase.Account.MosaicTransactionHostActor(
                addressBook: addressBook,
                profile: profile,
                network: network,
                attemptBinding: try #require(
                    MosaicHostFixture.makeAttemptBinding(
                        walletGeneration: 1
                    )
                ),
                selectedInputs: [firstInput, secondInput],
                outputAmountsSatoshis: [1],
                transactionPolicy: policy,
                attemptJournal: attemptJournal
            )
            Issue.record("Expected contribution overflow rejection")
        } catch let failure as OpalBase.Account.MosaicHostFailure {
            #expect(failure == .invalidContributionPolicy)
        }
        #expect(await journalProbe.readRecords().isEmpty)
        let spendable = await addressBook.listSpendableUTXOs()
        #expect(spendable.contains(firstInput))
        #expect(spendable.contains(secondInput))
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
            requiredExcessFeeSatoshis: fixture.reservationRequest
                .requiredExcessFeeSatoshis,
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

private extension AccountMosaicTransactionHostValidator {
    func makeReservationRequest(
        replacing request: OpalFusion.Host.MosaicReservationRequest,
        minimumExcessFeeSatoshis: UInt64,
        maximumExcessFeeSatoshis: UInt64,
        requiredExcessFeeSatoshis: UInt64
    ) throws -> OpalFusion.Host.MosaicReservationRequest {
        try .init(
            attemptIdentifier: request.attemptIdentifier,
            networkGenesisHash: request.networkGenesisHash,
            roundIdentifier: request.roundIdentifier,
            expiresAt: request.expiresAt,
            componentCount: request.componentCount,
            feeRateSatoshisPerByte: request.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: requiredExcessFeeSatoshis,
            transactionProfileIdentifier: request.transactionProfileIdentifier
        )
    }
}
#endif
