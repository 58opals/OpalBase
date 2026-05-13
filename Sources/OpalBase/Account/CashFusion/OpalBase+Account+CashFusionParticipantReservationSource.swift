// OpalBase+Account+CashFusionParticipantReservationSource.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    struct CashFusionParticipantReservationSource: OpalFusion.Host.ParticipantReservationSource {
        let reservation: CashFusionReservation

        func participantReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            try await reservation.participantReservation(for: roundIdentifier)
        }

        func participantReservation(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            try await reservation.participantReservation(for: context)
        }
    }
}
#endif
