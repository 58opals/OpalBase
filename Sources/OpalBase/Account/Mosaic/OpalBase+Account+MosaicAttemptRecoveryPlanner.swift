// OpalBase+Account+MosaicAttemptRecoveryPlanner.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    enum MosaicAttemptRecoveryPlanner {
        static func plan(
            for records: [MosaicAttemptJournal.Record]
        ) throws -> Plan {
            guard let first = records.first else { return .noAction }
            guard case let .reservationIntent(reference, _, _, _) = first else {
                throw Error.invalidFirstRecord
            }

            var state = State.reservationIntent(reference)
            var previous = first
            for record in records.dropFirst() {
                if record == previous { continue }
                guard record.reference == reference else {
                    throw Error.reservationReferenceMismatch
                }
                state = try state.applying(record)
                previous = record
            }
            return state.plan
        }
    }
}

private extension _OpalBase.Account.MosaicAttemptJournal.Record {
    var reference: OpalFusion.Host.MosaicReservationReference {
        switch self {
        case let .reservationIntent(reference, _, _, _),
             let .locallySigned(reference, _),
             let .releaseIntent(reference),
             let .released(reference),
             let .commitIntent(reference, _),
             let .committed(reference, _),
             let .broadcastIntent(reference, _),
             let .broadcastAccepted(reference, _, _):
            reference
        case let .reserved(lease):
            lease.reference
        case let .signingIntent(request):
            request.reservationReference
        }
    }
}

#endif
