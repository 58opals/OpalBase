// CashFusionWrappedSessionCapture.swift

#if os(macOS)
import OpalFusion
@testable import OpalBase

actor CashFusionWrappedSessionCapture {
    private var session: CashFusionFakeWrappedSession?
    private var configuration: OpalFusion.Client.Configuration?
    private var genesisHash: [UInt8]?
    private var joinPools: OpalFusion.ProtocolModel.JoinPools?
    private var participantReservationSource: (any OpalFusion.Host.ParticipantReservationSource)?
    private var reconnectPolicy: OpalFusion.Client.ReconnectPolicy?

    func store(
        _ session: CashFusionFakeWrappedSession,
        configuration: OpalFusion.Client.Configuration,
        genesisHash: [UInt8]?,
        joinPools: OpalFusion.ProtocolModel.JoinPools,
        participantReservationSource: any OpalFusion.Host.ParticipantReservationSource,
        reconnectPolicy: OpalFusion.Client.ReconnectPolicy
    ) {
        self.session = session
        self.configuration = configuration
        self.genesisHash = genesisHash
        self.joinPools = joinPools
        self.participantReservationSource = participantReservationSource
        self.reconnectPolicy = reconnectPolicy
    }

    func load() -> CashFusionFakeWrappedSession? {
        session
    }

    func loadConfiguration() -> OpalFusion.Client.Configuration? {
        configuration
    }

    func loadGenesisHash() -> [UInt8]? {
        genesisHash
    }

    func loadJoinPools() -> OpalFusion.ProtocolModel.JoinPools? {
        joinPools
    }

    func loadParticipantReservationSource() -> (any OpalFusion.Host.ParticipantReservationSource)? {
        participantReservationSource
    }

    func loadReconnectPolicy() -> OpalFusion.Client.ReconnectPolicy? {
        reconnectPolicy
    }
}
#endif
