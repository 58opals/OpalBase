// OpalBase+Account+CashFusionParticipantInputProvider.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    struct CashFusionParticipantInputProvider: OpalFusion.Host.ParticipantInputProvider {
        let reservation: OpalFusion.Host.ParticipantReservation

        func reservedInputs(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> [OpalFusion.Host.ParticipantInput] {
            _ = roundIdentifier
            return reservation.inputs
        }

        func participantReservation(
            for roundIdentifier: OpalFusion.Round.Identifier
        ) async throws -> OpalFusion.Host.ParticipantReservation {
            _ = roundIdentifier
            return reservation
        }
    }
}
