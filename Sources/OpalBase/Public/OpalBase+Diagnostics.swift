// OpalBase+Diagnostics.swift

import Foundation
@preconcurrency public import OpalDiagnostics

public extension OpalBase {
    /// Stable diagnostics names and trace helpers for correlating Wallet-facing OpalBase operations.
    enum Diagnostics {
        public typealias BufferPolicy = OpalDiagnostics.BufferPolicy
        public typealias Category = OpalDiagnostics.Category
        public typealias CategoryFilter = OpalDiagnostics.CategoryFilter
        public typealias Configuration = OpalDiagnostics.Configuration
        public typealias Event = OpalDiagnostics.Event
        public typealias Field = OpalDiagnostics.Field
        public typealias Level = OpalDiagnostics.Level
        public typealias Record = OpalDiagnostics.Record
        public typealias RecordQuery = OpalDiagnostics.RecordQuery
        public typealias TraceID = OpalDiagnostics.TraceID

        public static var configuration: Configuration {
            OpalDiagnostics.configuration
        }

        public static var currentTraceID: TraceID? {
            OpalDiagnostics.currentTraceID
        }

        public static var recentRecords: [Record] {
            OpalDiagnostics.recentRecords
        }

        public static func configure(_ configuration: Configuration) {
            OpalDiagnostics.configure(configuration)
        }

        public static func clearRecentRecords() {
            OpalDiagnostics.clearRecentRecords()
        }

        public static func recentRecords(matching query: RecordQuery) -> [Record] {
            OpalDiagnostics.recentRecords(matching: query)
        }

        public static func recentRecords(
            category: Category? = nil,
            level: Level? = nil,
            traceID: TraceID? = nil,
            event: Event? = nil,
            from startDate: Date? = nil,
            through endDate: Date? = nil
        ) -> [Record] {
            recentRecords(
                matching: .init(
                    category: category,
                    level: level,
                    traceID: traceID,
                    event: event,
                    from: startDate,
                    through: endDate
                )
            )
        }

        public static func withConfiguration<Success>(
            _ configuration: Configuration,
            operation: () throws -> Success
        ) rethrows -> Success {
            try OpalDiagnostics.withConfiguration(configuration, operation: operation)
        }

        public static nonisolated(nonsending) func withConfiguration<Success>(
            _ configuration: Configuration,
            operation: () async -> Success
        ) async -> Success {
            nonisolated(unsafe) let scopedOperation = operation
            return await OpalDiagnostics.withConfiguration(configuration) {
                await scopedOperation()
            }
        }

        public static nonisolated(nonsending) func withConfiguration<Success>(
            _ configuration: Configuration,
            operation: () async throws -> Success
        ) async throws -> Success {
            nonisolated(unsafe) let scopedOperation = operation
            return try await OpalDiagnostics.withConfiguration(configuration) {
                try await scopedOperation()
            }
        }

        public static func withTraceID<Success>(
            _ traceID: TraceID?,
            operation: () throws -> Success
        ) rethrows -> Success {
            try OpalDiagnostics.withTraceID(traceID, operation: operation)
        }

        public static nonisolated(nonsending) func withTraceID<Success>(
            _ traceID: TraceID?,
            operation: () async -> Success
        ) async -> Success {
            nonisolated(unsafe) let scopedOperation = operation
            return await OpalDiagnostics.withTraceID(traceID) {
                await scopedOperation()
            }
        }

        public static nonisolated(nonsending) func withTraceID<Success>(
            _ traceID: TraceID?,
            operation: () async throws -> Success
        ) async throws -> Success {
            nonisolated(unsafe) let scopedOperation = operation
            return try await OpalDiagnostics.withTraceID(traceID) {
                try await scopedOperation()
            }
        }

        public static func withTraceID<Success>(
            operation: () throws -> Success
        ) rethrows -> Success {
            try OpalDiagnostics.withTraceID(resolveTraceID(), operation: operation)
        }

        public static nonisolated(nonsending) func withTraceID<Success>(
            operation: () async -> Success
        ) async -> Success {
            await withTraceID(resolveTraceID(), operation: operation)
        }

        public static nonisolated(nonsending) func withTraceID<Success>(
            operation: () async throws -> Success
        ) async throws -> Success {
            try await withTraceID(resolveTraceID(), operation: operation)
        }

        public static func withNewTraceID<Success>(
            operation: (TraceID) throws -> Success
        ) rethrows -> Success {
            let traceID = TraceID()
            return try OpalDiagnostics.withTraceID(traceID) {
                try operation(traceID)
            }
        }

        public static nonisolated(nonsending) func withNewTraceID<Success>(
            operation: (TraceID) async -> Success
        ) async -> Success {
            let traceID = TraceID()
            nonisolated(unsafe) let scopedOperation = operation
            return await OpalDiagnostics.withTraceID(traceID) {
                await scopedOperation(traceID)
            }
        }

        public static nonisolated(nonsending) func withNewTraceID<Success>(
            operation: (TraceID) async throws -> Success
        ) async throws -> Success {
            let traceID = TraceID()
            nonisolated(unsafe) let scopedOperation = operation
            return try await OpalDiagnostics.withTraceID(traceID) {
                try await scopedOperation(traceID)
            }
        }

        public enum Categories {
            public static let wallet = OpalDiagnostics.Category(rawValue: "wallet")
            public static let account = OpalDiagnostics.Category(rawValue: "account")
            public static let addressBook = OpalDiagnostics.Category(rawValue: "address_book")
            public static let network = OpalDiagnostics.Category.network
            public static let cashFusion = OpalDiagnostics.Category(rawValue: "cash_fusion")
            public static let hedge = OpalDiagnostics.Category.hedge
            public static let transaction = OpalDiagnostics.Category(rawValue: "transaction")
            public static let claimable = OpalDiagnostics.Category(rawValue: "claimable")
            public static let tokenMetadata = OpalDiagnostics.Category(rawValue: "token_metadata")
            public static let storage = OpalDiagnostics.Category(rawValue: "storage")

            public static let all: [OpalDiagnostics.Category] = [
                wallet,
                account,
                addressBook,
                network,
                cashFusion,
                hedge,
                transaction,
                claimable,
                tokenMetadata,
                storage
            ]
        }

        public enum Events {
            public static let walletCreateStarted = OpalDiagnostics.Event(rawValue: "opalbase.wallet.create.started")
            public static let walletCreateSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.wallet.create.succeeded")
            public static let walletCreateFailed = OpalDiagnostics.Event(rawValue: "opalbase.wallet.create.failed")
            public static let walletAccountCreateStarted = OpalDiagnostics.Event(rawValue: "opalbase.wallet.account.create.started")
            public static let walletAccountCreateSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.wallet.account.create.succeeded")
            public static let walletAccountCreateFailed = OpalDiagnostics.Event(rawValue: "opalbase.wallet.account.create.failed")
            public static let walletAccountFetchSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.wallet.account.fetch.succeeded")
            public static let walletAccountFetchFailed = OpalDiagnostics.Event(rawValue: "opalbase.wallet.account.fetch.failed")
            public static let walletBalanceRefreshStarted = OpalDiagnostics.Event(rawValue: "opalbase.wallet.balance.refresh.started")
            public static let walletBalanceRefreshSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.wallet.balance.refresh.succeeded")
            public static let walletBalanceRefreshFailed = OpalDiagnostics.Event(rawValue: "opalbase.wallet.balance.refresh.failed")

            public static let accountCreateStarted = OpalDiagnostics.Event(rawValue: "opalbase.account.create.started")
            public static let accountCreateSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.account.create.succeeded")
            public static let accountCreateFailed = OpalDiagnostics.Event(rawValue: "opalbase.account.create.failed")
            public static let addressReserveStarted = OpalDiagnostics.Event(rawValue: "opalbase.address.reserve.started")
            public static let addressReserveSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.address.reserve.succeeded")
            public static let addressReserveFailed = OpalDiagnostics.Event(rawValue: "opalbase.address.reserve.failed")
            public static let addressSelectStarted = OpalDiagnostics.Event(rawValue: "opalbase.address.select.started")
            public static let addressSelectSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.address.select.succeeded")
            public static let addressSelectFailed = OpalDiagnostics.Event(rawValue: "opalbase.address.select.failed")
            public static let utxoRefreshStarted = OpalDiagnostics.Event(rawValue: "opalbase.utxo.refresh.started")
            public static let utxoRefreshSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.utxo.refresh.succeeded")
            public static let utxoRefreshFailed = OpalDiagnostics.Event(rawValue: "opalbase.utxo.refresh.failed")
            public static let transactionHistoryRefreshStarted = OpalDiagnostics.Event(rawValue: "opalbase.transaction.history.refresh.started")
            public static let transactionHistoryRefreshSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.transaction.history.refresh.succeeded")
            public static let transactionHistoryRefreshFailed = OpalDiagnostics.Event(rawValue: "opalbase.transaction.history.refresh.failed")
            public static let transactionConfirmationRefreshStarted = OpalDiagnostics.Event(rawValue: "opalbase.transaction.confirmation.refresh.started")
            public static let transactionConfirmationRefreshSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.transaction.confirmation.refresh.succeeded")
            public static let transactionConfirmationRefreshFailed = OpalDiagnostics.Event(rawValue: "opalbase.transaction.confirmation.refresh.failed")

            public static let spendPrepareStarted = OpalDiagnostics.Event(rawValue: "opalbase.spend.prepare.started")
            public static let spendPrepareSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.spend.prepare.succeeded")
            public static let spendPrepareFailed = OpalDiagnostics.Event(rawValue: "opalbase.spend.prepare.failed")
            public static let transactionBuildStarted = OpalDiagnostics.Event(rawValue: "opalbase.transaction.build.started")
            public static let transactionBuildSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.transaction.build.succeeded")
            public static let transactionBuildFailed = OpalDiagnostics.Event(rawValue: "opalbase.transaction.build.failed")
            public static let transactionBroadcastStarted = OpalDiagnostics.Event(rawValue: "opalbase.transaction.broadcast.started")
            public static let transactionBroadcastSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.transaction.broadcast.succeeded")
            public static let transactionBroadcastFailed = OpalDiagnostics.Event(rawValue: "opalbase.transaction.broadcast.failed")

            public static let cashFusionReadinessEvaluated = OpalDiagnostics.Event(rawValue: "opalbase.cash_fusion.readiness.evaluated")
            public static let cashFusionSessionPrepared = OpalDiagnostics.Event(rawValue: "opalbase.cash_fusion.session.prepared")
            public static let cashFusionSessionPrepareFailed = OpalDiagnostics.Event(rawValue: "opalbase.cash_fusion.session.prepare.failed")
            public static let cashFusionSessionStarted = OpalDiagnostics.Event(rawValue: "opalbase.cash_fusion.session.started")
            public static let cashFusionSessionFinalized = OpalDiagnostics.Event(rawValue: "opalbase.cash_fusion.session.finalized")

            public static let hedgeParticipantMaterialReserveStarted = OpalDiagnostics.Event(rawValue: "opalbase.hedge.participant_material.reserve.started")
            public static let hedgeParticipantMaterialReserved = OpalDiagnostics.Event(rawValue: "opalbase.hedge.participant_material.reserved")
            public static let hedgeParticipantMaterialReserveFailed = OpalDiagnostics.Event(rawValue: "opalbase.hedge.participant_material.reserve.failed")
            public static let hedgeFundingPrepareStarted = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.prepare.started")
            public static let hedgeFundingPrepareSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.prepare.succeeded")
            public static let hedgeFundingPrepareFailed = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.prepare.failed")
            public static let hedgeFundingBuildStarted = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.build.started")
            public static let hedgeFundingBuildSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.build.succeeded")
            public static let hedgeFundingBuildFailed = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.build.failed")
            public static let hedgeFundingBroadcastStarted = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.broadcast.started")
            public static let hedgeFundingBroadcastSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.broadcast.succeeded")
            public static let hedgeFundingBroadcastFailed = OpalDiagnostics.Event(rawValue: "opalbase.hedge.funding.broadcast.failed")
            public static let hedgeSettlementResolveStarted = OpalDiagnostics.Event(rawValue: "opalbase.hedge.settlement.resolve.started")
            public static let hedgeSettlementResolveSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.hedge.settlement.resolve.succeeded")
            public static let hedgeSettlementResolveFailed = OpalDiagnostics.Event(rawValue: "opalbase.hedge.settlement.resolve.failed")

            public static let claimableEnvelopeEncoded = OpalDiagnostics.Event(rawValue: "opalbase.claimable.envelope.encoded")
            public static let claimableEnvelopeDecodeSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.claimable.envelope.decode.succeeded")
            public static let claimableEnvelopeDecodeFailed = OpalDiagnostics.Event(rawValue: "opalbase.claimable.envelope.decode.failed")
            public static let claimableShareCodeEncoded = OpalDiagnostics.Event(rawValue: "opalbase.claimable.share_code.encoded")
            public static let claimableShareCodeDecodeSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.claimable.share_code.decode.succeeded")
            public static let claimableShareCodeDecodeFailed = OpalDiagnostics.Event(rawValue: "opalbase.claimable.share_code.decode.failed")
            public static let claimableStatusResolveStarted = OpalDiagnostics.Event(rawValue: "opalbase.claimable.status.resolve.started")
            public static let claimableStatusResolveSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.claimable.status.resolve.succeeded")
            public static let claimableStatusResolveFailed = OpalDiagnostics.Event(rawValue: "opalbase.claimable.status.resolve.failed")

            public static let tokenMetadataSyncStarted = OpalDiagnostics.Event(rawValue: "opalbase.token_metadata.sync.started")
            public static let tokenMetadataSyncSucceeded = OpalDiagnostics.Event(rawValue: "opalbase.token_metadata.sync.succeeded")
            public static let tokenMetadataSyncFailed = OpalDiagnostics.Event(rawValue: "opalbase.token_metadata.sync.failed")

            public static let networkFulcrumClientStarted = OpalDiagnostics.Event(rawValue: "opalbase.network.fulcrum.client.started")
            public static let networkFulcrumClientFailed = OpalDiagnostics.Event(rawValue: "opalbase.network.fulcrum.client.failed")
            public static let networkDiagnosticsSnapshotRecorded = OpalDiagnostics.Event(rawValue: "opalbase.network.diagnostics.snapshot.recorded")
            public static let networkDiagnosticsSubscriptionsRecorded = OpalDiagnostics.Event(rawValue: "opalbase.network.diagnostics.subscriptions.recorded")

            public static let all: [OpalDiagnostics.Event] = [
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

        public enum Fields {
            public static let operation = "operation"
            public static let module = "module"
            public static let accountIndex = "account_index"
            public static let accountCount = "account_count"
            public static let usage = "usage"
            public static let network = "network"
            public static let outcome = "outcome"
            public static let status = "status"
            public static let recipientCount = "recipient_count"
            public static let inputCount = "input_count"
            public static let outputCount = "output_count"
            public static let utxoCount = "utxo_count"
            public static let addressCount = "address_count"
            public static let transactionCount = "transaction_count"
            public static let tokenCategoryCount = "token_category_count"
            public static let tokenMetadataCount = "token_metadata_count"
            public static let includeUnconfirmed = "include_unconfirmed"
            public static let byteCount = "byte_count"
            public static let confirmationCount = "confirmation_count"
            public static let roundTraceID = "round_trace_id"
            public static let baseTraceID = "base_trace_id"
            public static let reconnectionAttemptCount = "reconnection_attempt_count"
            public static let reconnectSuccessCount = "reconnect_success_count"
            public static let inflightUnaryCallCount = "inflight_unary_call_count"
            public static let activeSubscriptionCount = "active_subscription_count"
            public static let errorCode = "error_code"
            public static let errorType = "error_type"

            public static let all: [String] = [
                operation, module, accountIndex, accountCount, usage, network, outcome, status,
                recipientCount, inputCount, outputCount, utxoCount, addressCount,
                transactionCount, tokenCategoryCount, tokenMetadataCount, includeUnconfirmed,
                byteCount, confirmationCount, roundTraceID, baseTraceID,
                reconnectionAttemptCount, reconnectSuccessCount,
                inflightUnaryCallCount, activeSubscriptionCount,
                errorCode, errorType
            ]
        }

        public enum ErrorCodes {
            public static let unknown = "unknown"
            public static let cancelled = "cancelled"
            public static let walletAccountAlreadyExists = "wallet.account_already_exists"
            public static let walletAccountNotFound = "wallet.account_not_found"
            public static let accountSnapshotMismatch = "account.snapshot_mismatch"
            public static let accountPaymentInvalid = "account.payment_invalid"
            public static let accountBalanceRefreshFailed = "account.balance_refresh_failed"
            public static let accountInsufficientFunds = "account.insufficient_funds"
            public static let accountCoinSelectionFailed = "account.coin_selection_failed"
            public static let accountTransactionHistoryRefreshFailed = "account.transaction_history_refresh_failed"
            public static let accountTransactionDetailsRefreshFailed = "account.transaction_details_refresh_failed"
            public static let accountTransactionBuildFailed = "account.transaction_build_failed"
            public static let accountBroadcastFailed = "account.broadcast_failed"
            public static let accountConfirmationQueryFailed = "account.confirmation_query_failed"
            public static let addressReservationFailed = "address.reservation_failed"
            public static let networkTransport = "network.transport"
            public static let networkServer = "network.server"
            public static let networkTimeout = "network.timeout"
            public static let networkEncoding = "network.encoding"
            public static let networkDecoding = "network.decoding"
            public static let networkProtocolViolation = "network.protocol_violation"
            public static let cashFusionInvalidRequest = "cash_fusion.invalid_request"
            public static let cashFusionReservationFailed = "cash_fusion.reservation_failed"
            public static let cashFusionOutputReservationFailed = "cash_fusion.output_reservation_failed"
            public static let cashFusionSessionFailed = "cash_fusion.session_failed"
            public static let hedgeFundingFailed = "hedge.funding_failed"
            public static let hedgeSettlementFailed = "hedge.settlement_failed"
            public static let claimableInvalidEnvelope = "claimable.invalid_envelope"
            public static let claimableInvalidShareCode = "claimable.invalid_share_code"
            public static let claimableStatusFailed = "claimable.status_failed"
            public static let tokenMetadataSyncFailed = "token_metadata.sync_failed"
            public static let storagePersistenceFailed = "storage.persistence_failed"

            public static let all: [String] = [
                unknown, cancelled,
                walletAccountAlreadyExists, walletAccountNotFound,
                accountSnapshotMismatch, accountPaymentInvalid, accountBalanceRefreshFailed, accountInsufficientFunds,
                accountCoinSelectionFailed, accountTransactionHistoryRefreshFailed, accountTransactionDetailsRefreshFailed,
                accountTransactionBuildFailed, accountBroadcastFailed, accountConfirmationQueryFailed,
                addressReservationFailed,
                networkTransport, networkServer, networkTimeout, networkEncoding,
                networkDecoding, networkProtocolViolation,
                cashFusionInvalidRequest, cashFusionReservationFailed,
                cashFusionOutputReservationFailed, cashFusionSessionFailed,
                hedgeFundingFailed, hedgeSettlementFailed,
                claimableInvalidEnvelope, claimableInvalidShareCode, claimableStatusFailed,
                tokenMetadataSyncFailed, storagePersistenceFailed
            ]
        }

        private static func resolveTraceID() -> TraceID {
            currentTraceID ?? TraceID()
        }
    }
}
