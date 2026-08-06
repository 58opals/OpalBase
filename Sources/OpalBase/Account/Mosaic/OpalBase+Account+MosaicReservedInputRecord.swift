// OpalBase+Account+MosaicReservedInputRecord.swift

#if os(macOS)
import OpalFusion

extension _OpalBase.Account {
    struct MosaicReservedInputRecord: Sendable {
        let unspentOutput: OpalBase.Transaction.Output.Unspent
        let signingKey: OpalBase.Key.SigningKey
        let participantInput: OpalFusion.Host.ParticipantInput
    }
}
#endif
