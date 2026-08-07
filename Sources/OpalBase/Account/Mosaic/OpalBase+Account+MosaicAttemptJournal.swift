// OpalBase+Account+MosaicAttemptJournal.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    /// Durable write-ahead records for one non-resumable Mosaic attempt.
    ///
    /// Records contain wallet-private material. A backend must append each record atomically and durably
    /// before returning. Serialization, encryption at rest, and storage location remain app-owned.
    struct MosaicAttemptJournal: Sendable {
        struct SelectedInput: Sendable, Equatable {
            let transactionHash: Data
            let outputIndex: UInt32
            let amountSatoshis: UInt64
            let lockingScript: Data

            init(_ input: OpalBase.Transaction.Output.Unspent) {
                transactionHash = input.previousTransactionHash.naturalOrder
                outputIndex = input.previousTransactionOutputIndex
                amountSatoshis = input.value
                lockingScript = input.lockingScript
            }
        }

        enum Record: Sendable, Equatable {
            case reservationIntent(
                reference: OpalFusion.Host.MosaicReservationReference,
                request: OpalFusion.Host.MosaicReservationRequest,
                selectedInputs: [SelectedInput],
                outputAmountsSatoshis: [UInt64]
            )
            case reserved(OpalFusion.Host.MosaicReservationLease)
            case signingIntent(OpalFusion.Host.MosaicTransactionSigningRequest)
            case locallySigned(
                reference: OpalFusion.Host.MosaicReservationReference,
                transaction: OpalFusion.Host.FinalizedTransaction
            )
            case releaseIntent(OpalFusion.Host.MosaicReservationReference)
            case released(OpalFusion.Host.MosaicReservationReference)
            case commitIntent(
                reference: OpalFusion.Host.MosaicReservationReference,
                transaction: OpalFusion.Host.MosaicCompleteTransaction
            )
            case committed(
                reference: OpalFusion.Host.MosaicReservationReference,
                transaction: OpalFusion.Host.MosaicCompleteTransaction
            )
            case broadcastIntent(
                reference: OpalFusion.Host.MosaicReservationReference,
                transaction: OpalFusion.Host.MosaicCompleteTransaction
            )
            case broadcastAccepted(
                reference: OpalFusion.Host.MosaicReservationReference,
                transaction: OpalFusion.Host.MosaicCompleteTransaction,
                transactionHash: OpalBase.Transaction.Hash
            )
        }

        private let recordAppender: @Sendable (Record) async throws -> Void

        init(
            appendRecord: @escaping @Sendable (Record) async throws -> Void
        ) {
            recordAppender = appendRecord
        }

        func append(_ record: Record) async throws {
            try await recordAppender(record)
        }
    }
}
#endif
