// MosaicHostFixture.swift

#if os(macOS)
import Foundation
import OpalFusion
import Testing
@testable import OpalBase

struct MosaicHostFixture {
    let account: OpalBase.Account
    let addressBook: OpalBase.Address.Book
    let selectedInput: OpalBase.Transaction.Output.Unspent
    let host: OpalBase.Account.MosaicTransactionHostActor
    let reservationRequest: OpalFusion.Host.MosaicReservationRequest
    let journalProbe: MosaicAttemptJournalProbeActor
    let profile: OpalFusion.Mosaic.Profile
    let network: OpalBase.Network.Environment

    static func make(
        walletGeneration: UInt64 = 7,
        transactionPolicy: OpalBase.Account.MosaicTransactionPolicy,
        network: OpalBase.Network.Environment = .chipnet,
        profile: OpalFusion.Mosaic.Profile = .opalV0,
        minimumExcessFeeSatoshis: UInt64? = nil,
        maximumExcessFeeSatoshis: UInt64? = nil,
        requiredExcessFeeSatoshis: UInt64? = nil,
        outputAmountsSatoshis suppliedOutputAmountsSatoshis: [UInt64]? = nil,
        journalProbe: MosaicAttemptJournalProbeActor = .init(),
        currentDate: @escaping @Sendable () -> Date = {
            Date(timeIntervalSince1970: 1_800_000_000)
        },
        reserveReceivingEntry: @escaping @Sendable (
            OpalBase.Address.Book,
            OpalBase.Address.Book.Entry
        ) async throws -> OpalBase.Address.Book.Entry = {
            addressBook,
            plannedEntry in
            try await addressBook.reserveMosaicReceivingEntry(plannedEntry)
        },
        sleepUntilDate: @escaping @Sendable (Date) async throws -> Void = { deadline in
            let interval = deadline.timeIntervalSinceNow
            guard interval > 0 else { return }
            try await Task.sleep(for: .seconds(interval))
        }
    ) async throws -> Self {
        let account = try await AccountTestFixtures.makeAccount()
        let selectedInput = try await AccountTestFixtures.addUnspentOutput(
            to: account,
            value: 100_000,
            usage: .change,
            hashByte: 0xa1
        )
        let addressBook = await account.addressBook
        let contributionPolicy = try #require(
            OpalBase.Account.MosaicProfileContributionPolicy(profile: profile)
        )
        let minimumExcessFeeSatoshis = minimumExcessFeeSatoshis
            ?? contributionPolicy.minimumExcessFeeSatoshis
        let maximumExcessFeeSatoshis = maximumExcessFeeSatoshis
            ?? contributionPolicy.maximumExcessFeeSatoshis
        let requiredExcessFeeSatoshis = requiredExcessFeeSatoshis
            ?? contributionPolicy.maximumExcessFeeSatoshis
        let outputAmountsSatoshis: [UInt64]
        if let suppliedOutputAmountsSatoshis {
            outputAmountsSatoshis = suppliedOutputAmountsSatoshis
        } else if profile == .opalV0 {
            outputAmountsSatoshis = [90_000]
        } else {
            let localContribution = try #require(
                contributionPolicy.expectedLocalContributionSatoshis(
                    inputCount: 1,
                    outputCount: 1,
                    requiredExcessFeeSatoshis: requiredExcessFeeSatoshis
                )
            )
            outputAmountsSatoshis = [selectedInput.value - localContribution]
        }
        let expirationDate = Date(timeIntervalSince1970: 1_900_000_000)
        let identifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000007")
        )
        let attemptBinding = try #require(
            makeAttemptBinding(
                walletGeneration: walletGeneration,
                walletReservationIdentifier: identifier
            )
        )
        let attemptJournal = try await journalProbe
            .makeBoundJournalForTesting(attemptBinding)
        let host = try OpalBase.Account.MosaicTransactionHostActor(
            addressBook: addressBook,
            profile: profile,
            network: network,
            attemptBinding: attemptBinding,
            selectedInputs: [selectedInput],
            outputAmountsSatoshis: outputAmountsSatoshis,
            transactionPolicy: transactionPolicy,
            attemptJournal: attemptJournal,
            currentDate: currentDate,
            reserveReceivingEntry: reserveReceivingEntry,
            sleepUntilDate: sleepUntilDate
        )
        let request = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: [UInt8](attemptBinding.attemptIdentifier),
            networkGenesisHash: network.mosaicGenesisHash,
            roundIdentifier: Array(repeating: 0x33, count: 32),
            expiresAt: expirationDate,
            componentCount: profile.rosterPolicy.componentCountPerContributor,
            feeRateSatoshisPerByte: 1,
            minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: requiredExcessFeeSatoshis,
            transactionProfileIdentifier: profile.transactionProfileIdentifier
        )
        return .init(
            account: account,
            addressBook: addressBook,
            selectedInput: selectedInput,
            host: host,
            reservationRequest: request,
            journalProbe: journalProbe,
            profile: profile,
            network: network
        )
    }

    static func makeAttemptBinding(
        walletGeneration: UInt64 = 7,
        walletReservationIdentifier: UUID = UUID(),
        attemptIdentifierByte: UInt8 = 0x11,
        generationIdentifierByte: UInt8 = 0x22,
        materialIdentifierByte: UInt8 = 0x33
    ) -> OpalBase.Account.MosaicAttemptBinding? {
        .init(
            attemptIdentifier: Data(
                repeating: attemptIdentifierByte,
                count: 32
            ),
            generationIdentifier: Data(
                repeating: generationIdentifierByte,
                count: 32
            ),
            materialIdentifier: Data(
                repeating: materialIdentifierByte,
                count: 32
            ),
            walletReservationReference: .init(
                identifier: walletReservationIdentifier,
                generation: walletGeneration
            )
        )
    }

    func reserve() async throws -> OpalFusion.Host.MosaicReservationLease {
        try await host.reserveMosaicContribution(for: reservationRequest)
    }

    func makeSigningRequest(
        lease: OpalFusion.Host.MosaicReservationLease,
        transaction: OpalBase.Transaction? = nil,
        transcriptByte: UInt8 = 0x44,
        transcriptProfile: OpalFusion.Mosaic.Profile? = nil,
        transactionProfileIdentifier: String? = nil
    ) throws -> OpalFusion.Host.MosaicTransactionSigningRequest {
        let unsignedTransaction = transaction ?? OpalBase.Transaction(
            version: 2,
            inputs: [
                .init(
                    previousTransactionHash: selectedInput.previousTransactionHash,
                    previousTransactionOutputIndex: selectedInput.previousTransactionOutputIndex,
                    unlockingScript: Data()
                )
            ],
            outputs: lease.participantReservation.outputs.map {
                .init(
                    value: $0.amountSatoshis,
                    lockingScript: Data($0.lockingScriptBytes)
                )
            },
            lockTime: 0
        )
        let unsignedTransactionBytes = [UInt8](try unsignedTransaction.encode())
        return try .init(
            reservationReference: lease.reference,
            roundIdentifier: reservationRequest.roundIdentifier,
            transcriptBinding: try Self.makeTranscriptBinding(
                profile: transcriptProfile ?? profile,
                unsignedTransactionBytes: unsignedTransactionBytes,
                discriminator: transcriptByte
            ),
            unsignedTransactionBytes: unsignedTransactionBytes,
            spentInputs: lease.participantReservation.inputs,
            localInputIndices: [0],
            expectedLocalOutputs: lease.participantReservation.outputs,
            feeRateSatoshisPerByte: reservationRequest.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: reservationRequest.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: reservationRequest.maximumExcessFeeSatoshis,
            requiredExcessFeeSatoshis: reservationRequest
                .requiredExcessFeeSatoshis,
            transactionProfileIdentifier: transactionProfileIdentifier
                ?? reservationRequest.transactionProfileIdentifier
        )
    }

    static func makeTranscriptBinding(
        profile: OpalFusion.Mosaic.Profile,
        unsignedTransactionBytes: [UInt8],
        discriminator: UInt8
    ) throws -> OpalFusion.Host.MosaicTranscriptBinding {
        let manifestDigest = Array(repeating: discriminator, count: 32)
        let commitmentSetDigest = Array(repeating: UInt8(0x42), count: 32)
        let componentSetDigest = Array(repeating: UInt8(0x43), count: 32)
        let root = try OpalFusion.Host.MosaicTranscriptBinding.transcriptRoot(
            profile: profile,
            manifestDigest: manifestDigest,
            commitmentSetDigest: commitmentSetDigest,
            componentSetDigest: componentSetDigest,
            unsignedTransactionBytes: unsignedTransactionBytes
        )
        return try .init(
            profile: profile,
            manifestDigest: manifestDigest,
            commitmentSetDigest: commitmentSetDigest,
            componentSetDigest: componentSetDigest,
            unsignedTransactionBytes: unsignedTransactionBytes,
            acknowledgedTranscriptRoot: root
        )
    }
}
#endif
