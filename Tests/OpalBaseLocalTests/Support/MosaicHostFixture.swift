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

    static func make(
        generation: UInt64 = 7,
        transactionPolicy: OpalBase.Account.MosaicTransactionPolicy,
        network: OpalBase.Network.Environment = .chipnet,
        profile: OpalFusion.Mosaic.Profile = .draft1,
        minimumExcessFeeSatoshis: UInt64 = 100,
        maximumExcessFeeSatoshis: UInt64 = 200,
        journalProbe: MosaicAttemptJournalProbeActor = .init(),
        reserveReceivingEntry: @escaping @Sendable (
            OpalBase.Address.Book
        ) async throws -> OpalBase.Address.Book.Entry = { addressBook in
            try await addressBook.reserveMosaicReceivingEntry()
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
        let currentDate = Date(timeIntervalSince1970: 1_800_000_000)
        let expirationDate = Date(timeIntervalSince1970: 1_900_000_000)
        let identifier = try #require(
            UUID(uuidString: "00000000-0000-0000-0000-000000000007")
        )
        let host = try OpalBase.Account.MosaicTransactionHostActor(
            addressBook: addressBook,
            network: network,
            generation: generation,
            selectedInputs: [selectedInput],
            outputAmountsSatoshis: [90_000],
            transactionPolicy: transactionPolicy,
            attemptJournal: journalProbe.makeJournal(),
            currentDate: { currentDate },
            makeReservationIdentifier: { identifier },
            reserveReceivingEntry: reserveReceivingEntry,
            sleepUntilDate: sleepUntilDate
        )
        let request = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: [0x11],
            networkGenesisHash: network.mosaicGenesisHash,
            roundIdentifier: Array(repeating: 0x33, count: 32),
            expiresAt: expirationDate,
            componentCount: 2,
            feeRateSatoshisPerByte: 1,
            minimumExcessFeeSatoshis: minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: maximumExcessFeeSatoshis,
            transactionProfileIdentifier: profile.transactionProfileIdentifier
        )
        return .init(
            account: account,
            addressBook: addressBook,
            selectedInput: selectedInput,
            host: host,
            reservationRequest: request,
            journalProbe: journalProbe,
            profile: profile
        )
    }

    func reserve() async throws -> OpalFusion.Host.MosaicReservationLease {
        try await host.reserveMosaicContribution(for: reservationRequest)
    }

    func makeSigningRequest(
        lease: OpalFusion.Host.MosaicReservationLease,
        transaction: OpalBase.Transaction? = nil,
        transcriptByte: UInt8 = 0x44,
        transcriptProfile: OpalFusion.Mosaic.Profile? = nil
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
            transactionProfileIdentifier: reservationRequest.transactionProfileIdentifier
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
