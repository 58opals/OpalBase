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

    static func make(
        generation: UInt64 = 7,
        transactionPolicy: OpalBase.Account.MosaicTransactionPolicy,
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
            network: .chipnet,
            generation: generation,
            selectedInputs: [selectedInput],
            outputAmountsSatoshis: [90_000],
            transactionPolicy: transactionPolicy,
            currentDate: { currentDate },
            makeReservationIdentifier: { identifier },
            reserveReceivingEntry: reserveReceivingEntry,
            sleepUntilDate: sleepUntilDate
        )
        let request = try OpalFusion.Host.MosaicReservationRequest(
            attemptIdentifier: [0x11],
            networkGenesisHash: OpalBase.Network.Environment.chipnet.mosaicGenesisHash,
            roundIdentifier: Array(repeating: 0x33, count: 32),
            expiresAt: expirationDate,
            componentCount: 2,
            feeRateSatoshisPerByte: 1,
            minimumExcessFeeSatoshis: 100,
            maximumExcessFeeSatoshis: 200,
            transactionProfileIdentifier: "mosaic-bch-p2pkh-draft"
        )
        return .init(
            account: account,
            addressBook: addressBook,
            selectedInput: selectedInput,
            host: host,
            reservationRequest: request
        )
    }

    func reserve() async throws -> OpalFusion.Host.MosaicReservationLease {
        try await host.reserveMosaicContribution(for: reservationRequest)
    }

    func makeSigningRequest(
        lease: OpalFusion.Host.MosaicReservationLease,
        transaction: OpalBase.Transaction? = nil,
        transcriptByte: UInt8 = 0x44
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
        return try .init(
            reservationReference: lease.reference,
            roundIdentifier: reservationRequest.roundIdentifier,
            transcriptRoot: Array(repeating: transcriptByte, count: 32),
            unsignedTransactionBytes: [UInt8](try unsignedTransaction.encode()),
            spentInputs: lease.participantReservation.inputs,
            localInputIndices: [0],
            expectedLocalOutputs: lease.participantReservation.outputs,
            feeRateSatoshisPerByte: reservationRequest.feeRateSatoshisPerByte,
            minimumExcessFeeSatoshis: reservationRequest.minimumExcessFeeSatoshis,
            maximumExcessFeeSatoshis: reservationRequest.maximumExcessFeeSatoshis,
            transactionProfileIdentifier: reservationRequest.transactionProfileIdentifier
        )
    }
}
#endif
