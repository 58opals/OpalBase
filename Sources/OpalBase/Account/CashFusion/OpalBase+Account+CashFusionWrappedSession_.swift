// OpalBase+Account+CashFusionWrappedSession_.swift

#if os(macOS)
import Foundation
import OpalFusion

extension _OpalBase.Account {
    protocol CashFusionWrappedSession: Sendable {
        func start() async
        func stop() async
        var currentSnapshot: OpalFusion.Client.Session.Snapshot { get async }
    }

    typealias CashFusionWrappedSessionBuilder = @Sendable (
        OpalFusion.Client.Configuration,
        [UInt8]?,
        OpalFusion.ProtocolModel.JoinPools,
        any OpalFusion.Host.ParticipantReservationSource,
        any OpalFusion.Host.TransactionAssembler,
        (any OpalFusion.Host.EventObserver)?,
        (any OpalFusion.Client.StateObserver)?,
        OpalFusion.Client.ReconnectPolicy
    ) async -> any CashFusionWrappedSession

    static let defaultCashFusionWrappedSessionBuilder: CashFusionWrappedSessionBuilder = {
        configuration,
        genesisHash,
        joinPools,
        participantReservationSource,
        transactionAssembler,
        eventObserver,
        stateObserver,
        reconnectPolicy in
        OpalFusion.Client.Session(
            configuration: configuration,
            genesisHash: genesisHash,
            joinPools: joinPools,
            hostParticipantReservationSource: participantReservationSource,
            hostTransactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver,
            reconnectPolicy: reconnectPolicy
        )
    }
}

extension OpalFusion.Client.Session: _OpalBase.Account.CashFusionWrappedSession {}
#endif
