// OpalBase+Account+CashFusionParticipantReservationSource.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    struct CashFusionParticipantReservationSource: OpalFusion.Host.ParticipantReservationSource {
        let reservation: CashFusionReservation

        func reserveParticipant(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            try await reservation.reserveParticipant(for: roundIdentifier)
        }

        func reserveParticipant(
            for context: OpalFusion.Host.ParticipantReservationContext
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            try await reservation.reserveParticipant(for: context)
        }
    }
}
#endif
