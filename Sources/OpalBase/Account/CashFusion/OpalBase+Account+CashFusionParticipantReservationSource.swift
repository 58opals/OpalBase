#if os(macOS)
// OpalBase+Account+CashFusionParticipantReservationSource.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    struct CashFusionParticipantReservationSource: OpalFusion.Host.ParticipantReservationSource {
        let reservation: OpalFusion.Host.ParticipantReservation

        func participantReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            _ = roundIdentifier
            return reservation
        }
    }
}
#endif
