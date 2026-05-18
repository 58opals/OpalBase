// OpalDiagnostics+Event+OpalBase.swift

@preconcurrency public import OpalDiagnostics

public extension OpalDiagnostics.Event {
    static let walletCreateStarted = Self(rawValue: "opalbase.wallet.create.started")
    static let walletCreateSucceeded = Self(rawValue: "opalbase.wallet.create.succeeded")
    static let walletCreateFailed = Self(rawValue: "opalbase.wallet.create.failed")
    static let walletAccountCreateStarted = Self(rawValue: "opalbase.wallet.account.create.started")
    static let walletAccountCreateSucceeded = Self(rawValue: "opalbase.wallet.account.create.succeeded")
    static let walletAccountCreateFailed = Self(rawValue: "opalbase.wallet.account.create.failed")
    static let walletAccountFetchSucceeded = Self(rawValue: "opalbase.wallet.account.fetch.succeeded")
    static let walletAccountFetchFailed = Self(rawValue: "opalbase.wallet.account.fetch.failed")
    static let walletBalanceRefreshStarted = Self(rawValue: "opalbase.wallet.balance.refresh.started")
    static let walletBalanceRefreshSucceeded = Self(rawValue: "opalbase.wallet.balance.refresh.succeeded")
    static let walletBalanceRefreshFailed = Self(rawValue: "opalbase.wallet.balance.refresh.failed")

    static let accountCreateStarted = Self(rawValue: "opalbase.account.create.started")
    static let accountCreateSucceeded = Self(rawValue: "opalbase.account.create.succeeded")
    static let accountCreateFailed = Self(rawValue: "opalbase.account.create.failed")
    static let addressReserveStarted = Self(rawValue: "opalbase.address.reserve.started")
    static let addressReserveSucceeded = Self(rawValue: "opalbase.address.reserve.succeeded")
    static let addressReserveFailed = Self(rawValue: "opalbase.address.reserve.failed")
    static let addressSelectStarted = Self(rawValue: "opalbase.address.select.started")
    static let addressSelectSucceeded = Self(rawValue: "opalbase.address.select.succeeded")
    static let addressSelectFailed = Self(rawValue: "opalbase.address.select.failed")
    static let utxoRefreshStarted = Self(rawValue: "opalbase.utxo.refresh.started")
    static let utxoRefreshSucceeded = Self(rawValue: "opalbase.utxo.refresh.succeeded")
    static let utxoRefreshFailed = Self(rawValue: "opalbase.utxo.refresh.failed")
    static let transactionHistoryRefreshStarted = Self(rawValue: "opalbase.transaction.history.refresh.started")
    static let transactionHistoryRefreshSucceeded = Self(rawValue: "opalbase.transaction.history.refresh.succeeded")
    static let transactionHistoryRefreshFailed = Self(rawValue: "opalbase.transaction.history.refresh.failed")
    static let transactionConfirmationRefreshStarted = Self(rawValue: "opalbase.transaction.confirmation.refresh.started")
    static let transactionConfirmationRefreshSucceeded = Self(rawValue: "opalbase.transaction.confirmation.refresh.succeeded")
    static let transactionConfirmationRefreshFailed = Self(rawValue: "opalbase.transaction.confirmation.refresh.failed")

    static let spendPrepareStarted = Self(rawValue: "opalbase.spend.prepare.started")
    static let spendPrepareSucceeded = Self(rawValue: "opalbase.spend.prepare.succeeded")
    static let spendPrepareFailed = Self(rawValue: "opalbase.spend.prepare.failed")
    static let transactionBuildStarted = Self(rawValue: "opalbase.transaction.build.started")
    static let transactionBuildSucceeded = Self(rawValue: "opalbase.transaction.build.succeeded")
    static let transactionBuildFailed = Self(rawValue: "opalbase.transaction.build.failed")
    static let transactionBroadcastStarted = Self(rawValue: "opalbase.transaction.broadcast.started")
    static let transactionBroadcastSucceeded = Self(rawValue: "opalbase.transaction.broadcast.succeeded")
    static let transactionBroadcastFailed = Self(rawValue: "opalbase.transaction.broadcast.failed")

    static let cashFusionReadinessEvaluated = Self(rawValue: "opalbase.cash_fusion.readiness.evaluated")
    static let cashFusionSessionPrepared = Self(rawValue: "opalbase.cash_fusion.session.prepared")
    static let cashFusionSessionPrepareFailed = Self(rawValue: "opalbase.cash_fusion.session.prepare.failed")
    static let cashFusionSessionStarted = Self(rawValue: "opalbase.cash_fusion.session.started")
    static let cashFusionSessionFinalized = Self(rawValue: "opalbase.cash_fusion.session.finalized")

    static let hedgeParticipantMaterialReserveStarted = Self(rawValue: "opalbase.hedge.participant_material.reserve.started")
    static let hedgeParticipantMaterialReserved = Self(rawValue: "opalbase.hedge.participant_material.reserved")
    static let hedgeParticipantMaterialReserveFailed = Self(rawValue: "opalbase.hedge.participant_material.reserve.failed")
    static let hedgeFundingPrepareStarted = Self(rawValue: "opalbase.hedge.funding.prepare.started")
    static let hedgeFundingPrepareSucceeded = Self(rawValue: "opalbase.hedge.funding.prepare.succeeded")
    static let hedgeFundingPrepareFailed = Self(rawValue: "opalbase.hedge.funding.prepare.failed")
    static let hedgeFundingBuildStarted = Self(rawValue: "opalbase.hedge.funding.build.started")
    static let hedgeFundingBuildSucceeded = Self(rawValue: "opalbase.hedge.funding.build.succeeded")
    static let hedgeFundingBuildFailed = Self(rawValue: "opalbase.hedge.funding.build.failed")
    static let hedgeFundingBroadcastStarted = Self(rawValue: "opalbase.hedge.funding.broadcast.started")
    static let hedgeFundingBroadcastSucceeded = Self(rawValue: "opalbase.hedge.funding.broadcast.succeeded")
    static let hedgeFundingBroadcastFailed = Self(rawValue: "opalbase.hedge.funding.broadcast.failed")
    static let hedgeSettlementResolveStarted = Self(rawValue: "opalbase.hedge.settlement.resolve.started")
    static let hedgeSettlementResolveSucceeded = Self(rawValue: "opalbase.hedge.settlement.resolve.succeeded")
    static let hedgeSettlementResolveFailed = Self(rawValue: "opalbase.hedge.settlement.resolve.failed")

    static let claimableEnvelopeEncoded = Self(rawValue: "opalbase.claimable.envelope.encoded")
    static let claimableEnvelopeDecodeSucceeded = Self(rawValue: "opalbase.claimable.envelope.decode.succeeded")
    static let claimableEnvelopeDecodeFailed = Self(rawValue: "opalbase.claimable.envelope.decode.failed")
    static let claimableShareCodeEncoded = Self(rawValue: "opalbase.claimable.share_code.encoded")
    static let claimableShareCodeDecodeSucceeded = Self(rawValue: "opalbase.claimable.share_code.decode.succeeded")
    static let claimableShareCodeDecodeFailed = Self(rawValue: "opalbase.claimable.share_code.decode.failed")
    static let claimableStatusResolveStarted = Self(rawValue: "opalbase.claimable.status.resolve.started")
    static let claimableStatusResolveSucceeded = Self(rawValue: "opalbase.claimable.status.resolve.succeeded")
    static let claimableStatusResolveFailed = Self(rawValue: "opalbase.claimable.status.resolve.failed")

    static let tokenMetadataSyncStarted = Self(rawValue: "opalbase.token_metadata.sync.started")
    static let tokenMetadataSyncSucceeded = Self(rawValue: "opalbase.token_metadata.sync.succeeded")
    static let tokenMetadataSyncFailed = Self(rawValue: "opalbase.token_metadata.sync.failed")

    static let networkFulcrumClientStarted = Self(rawValue: "opalbase.network.fulcrum.client.started")
    static let networkFulcrumClientFailed = Self(rawValue: "opalbase.network.fulcrum.client.failed")
    static let networkDiagnosticsSnapshotRecorded = Self(rawValue: "opalbase.network.diagnostics.snapshot.recorded")
    static let networkDiagnosticsSubscriptionsRecorded = Self(rawValue: "opalbase.network.diagnostics.subscriptions.recorded")

    static let all: [Self] = [
        walletCreateStarted, walletCreateSucceeded, walletCreateFailed,
        walletAccountCreateStarted, walletAccountCreateSucceeded, walletAccountCreateFailed,
        walletAccountFetchSucceeded, walletAccountFetchFailed,
        walletBalanceRefreshStarted, walletBalanceRefreshSucceeded, walletBalanceRefreshFailed,
        accountCreateStarted, accountCreateSucceeded, accountCreateFailed,
        addressReserveStarted, addressReserveSucceeded, addressReserveFailed,
        addressSelectStarted, addressSelectSucceeded, addressSelectFailed,
        utxoRefreshStarted, utxoRefreshSucceeded, utxoRefreshFailed,
        transactionHistoryRefreshStarted, transactionHistoryRefreshSucceeded, transactionHistoryRefreshFailed,
        transactionConfirmationRefreshStarted, transactionConfirmationRefreshSucceeded, transactionConfirmationRefreshFailed,
        spendPrepareStarted, spendPrepareSucceeded, spendPrepareFailed,
        transactionBuildStarted, transactionBuildSucceeded, transactionBuildFailed,
        transactionBroadcastStarted, transactionBroadcastSucceeded, transactionBroadcastFailed,
        cashFusionReadinessEvaluated, cashFusionSessionPrepared, cashFusionSessionPrepareFailed,
        cashFusionSessionStarted, cashFusionSessionFinalized,
        hedgeParticipantMaterialReserveStarted,
        hedgeParticipantMaterialReserved,
        hedgeParticipantMaterialReserveFailed,
        hedgeFundingPrepareStarted, hedgeFundingPrepareSucceeded, hedgeFundingPrepareFailed,
        hedgeFundingBuildStarted, hedgeFundingBuildSucceeded, hedgeFundingBuildFailed,
        hedgeFundingBroadcastStarted, hedgeFundingBroadcastSucceeded, hedgeFundingBroadcastFailed,
        hedgeSettlementResolveStarted, hedgeSettlementResolveSucceeded, hedgeSettlementResolveFailed,
        claimableEnvelopeEncoded,
        claimableEnvelopeDecodeSucceeded, claimableEnvelopeDecodeFailed,
        claimableShareCodeEncoded,
        claimableShareCodeDecodeSucceeded, claimableShareCodeDecodeFailed,
        claimableStatusResolveStarted, claimableStatusResolveSucceeded, claimableStatusResolveFailed,
        tokenMetadataSyncStarted, tokenMetadataSyncSucceeded, tokenMetadataSyncFailed,
        networkFulcrumClientStarted, networkFulcrumClientFailed,
        networkDiagnosticsSnapshotRecorded, networkDiagnosticsSubscriptionsRecorded
    ]
}
