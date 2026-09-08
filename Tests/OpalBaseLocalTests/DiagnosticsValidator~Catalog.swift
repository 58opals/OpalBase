// DiagnosticsValidator~Catalog.swift

import Foundation
import OpalDiagnostics
import Testing
import OpalBaseTestSupport
import SwiftFulcrum
@testable import OpalBase

extension DiagnosticsValidator {
    @Test("public diagnostics catalog exposes stable names")
    func publicDiagnosticsCatalogExposesStableNames() {
        #expect(Set(OpalDiagnostics.Category.all) == [
            OpalDiagnostics.Category.wallet,
            OpalDiagnostics.Category.account,
            OpalDiagnostics.Category.addressBook,
            OpalDiagnostics.Category.network,
            OpalDiagnostics.Category.cashFusion,
            OpalDiagnostics.Category.hedge,
            OpalDiagnostics.Category.transaction,
            OpalDiagnostics.Category.claimable,
            OpalDiagnostics.Category.tokenMetadata,
            OpalDiagnostics.Category.storage
        ])

        #expect(OpalDiagnostics.ErrorCode.all.contains(OpalDiagnostics.ErrorCode.cashFusionReservationFailed))
    }

    @Test("public diagnostics catalog contains representative events", arguments: catalogEvents)
    func verifyCatalogEventMembership(_ event: OpalDiagnostics.Event) {
        #expect(OpalDiagnostics.Event.all.contains(event))
    }

    @Test("stable diagnostics event raw values", arguments: eventRawValues)
    func verifyEventRawValue(event: OpalDiagnostics.Event, expectedValue: String) {
        #expect(event.rawValue == expectedValue)
    }

    @Test("stable diagnostics field names", arguments: fieldRawValues)
    func verifyFieldRawValue(fieldName: String, expectedValue: String) {
        #expect(fieldName == expectedValue)
    }

    @Test("public diagnostics catalog contains representative fields", arguments: catalogFields)
    func verifyCatalogFieldMembership(_ fieldName: String) {
        #expect(OpalDiagnostics.Field.Name.all.contains(fieldName))
    }

    @Test("stable error code raw values", arguments: errorCodeRawValues)
    func verifyErrorCodeRawValue(errorCode: OpalDiagnostics.ErrorCode, expectedValue: String) {
        #expect(errorCode.rawValue == expectedValue)
    }

    private static let catalogEvents: [OpalDiagnostics.Event] = [
        .walletCreateStarted,
        .addressReserveSucceeded,
        .utxoRefreshFailed,
        .spendPrepareStarted,
        .cashFusionSessionFinalized,
        .claimableShareCodeDecodeFailed,
        .tokenMetadataSyncSucceeded,
        .networkDiagnosticsCountersRecorded,
        .networkDiagnosticsRegistryUpdateRecorded
    ]

    private static let eventRawValues: [(OpalDiagnostics.Event, String)] = [
        (.networkDiagnosticsCountersRecorded, "opalbase.network.diagnostics.snapshot.recorded"),
        (.networkDiagnosticsRegistryUpdateRecorded, "opalbase.network.diagnostics.subscriptions.recorded")
    ]

    private static let fieldRawValues: [(String, String)] = [
        (OpalDiagnostics.Field.Name.errorCode, "error_code"),
        (OpalDiagnostics.Field.Name.accountIndex, "account_index"),
        (OpalDiagnostics.Field.Name.accountCount, "account_count"),
        (OpalDiagnostics.Field.Name.tokenMetadataCount, "token_metadata_count"),
        (OpalDiagnostics.Field.Name.errorReason, "error_reason"),
        (OpalDiagnostics.Field.Name.serverCode, "server_code"),
        (OpalDiagnostics.Field.Name.closeCode, "close_code"),
        (OpalDiagnostics.Field.Name.timeoutSeconds, "timeout_seconds"),
        (OpalDiagnostics.Field.Name.minimumVersion, "minimum_version"),
        (OpalDiagnostics.Field.Name.maximumVersion, "maximum_version"),
        (OpalDiagnostics.Field.Name.privateErrorMetadata, "error_private_metadata")
    ]

    private static let catalogFields: [String] = [
        OpalDiagnostics.Field.Name.reconnectionAttemptCount,
        OpalDiagnostics.Field.Name.activeSubscriptionCount,
        OpalDiagnostics.Field.Name.errorType,
        OpalDiagnostics.Field.Name.errorMessage
    ]

    private static let errorCodeRawValues: [(OpalDiagnostics.ErrorCode, String)] = [
        (.walletAccountAlreadyExists, "wallet.account_already_exists"),
        (.walletAccountNotFound, "wallet.account_not_found"),
        (.walletSecurityProfileViolation, "wallet.security_profile_violation"),
        (.accountBalanceRefreshFailed, "account.balance_refresh_failed"),
        (.accountTransactionHistoryRefreshFailed, "account.transaction_history_refresh_failed"),
        (.networkTransport, "network.transport"),
        (.networkServer, "network.server"),
        (.networkTimeout, "network.timeout"),
        (.networkEncoding, "network.encoding"),
        (.networkDecoding, "network.decoding"),
        (.networkProtocolViolation, "network.protocol_violation"),
        (.claimableInvalidShareCode, "claimable.invalid_share_code")
    ]
}
