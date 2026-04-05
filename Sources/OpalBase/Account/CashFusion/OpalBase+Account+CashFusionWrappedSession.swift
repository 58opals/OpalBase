// OpalBase+Account+CashFusionWrappedSession.swift

import Foundation
import OpalFusion

extension _OpalBase.Account {
    protocol CashFusionWrappedSession: Sendable {
        func start() async
        func stop() async
        func snapshot() async -> OpalFusion.Client.Session.Snapshot
    }

    typealias CashFusionWrappedSessionFactory = @Sendable (
        OpalFusion.Client.Configuration,
        [UInt8]?,
        OpalFusion.ProtocolModel.JoinPools,
        any OpalFusion.Host.ParticipantInputProvider,
        any OpalFusion.Host.TransactionAssembler,
        (any OpalFusion.Host.EventObserver)?,
        (any OpalFusion.Client.StateObserver)?
    ) -> any CashFusionWrappedSession

    static let defaultCashFusionWrappedSessionFactory: CashFusionWrappedSessionFactory = {
        configuration,
        genesisHash,
        joinPools,
        participantInputProvider,
        transactionAssembler,
        eventObserver,
        stateObserver in
        OpalFusion.Client.Session(
            configuration: configuration,
            genesisHash: genesisHash,
            joinPools: joinPools,
            participantInputProvider: participantInputProvider,
            transactionAssembler: transactionAssembler,
            eventObserver: eventObserver,
            stateObserver: stateObserver
        )
    }
}

extension OpalFusion.Client.Session: _OpalBase.Account.CashFusionWrappedSession {}
