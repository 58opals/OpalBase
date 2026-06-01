// OpalBase+Account+CashFusionRoundReservation.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    struct CashFusionRoundReservation: Sendable {
        let roundIdentifier: OpalFusion.Round.Identifier
        let reservedReceivingEntries: [OpalBase.Address.Book.Entry]
        let participantOutputs: [OpalFusion.Host.ParticipantOutput]
        let participantReservation: OpalFusion.Host.ParticipantReservation
    }
}
#endif
