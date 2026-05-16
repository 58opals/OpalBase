// OpalBaseDiagnostics.swift

import Foundation
import OpalDiagnostics
import SwiftFulcrum

enum OpalBaseDiagnostics {
    typealias Diagnostics = OpalBase.Diagnostics

    static func record(
        _ event: OpalDiagnostics.Event,
        category: OpalDiagnostics.Category,
        level: OpalDiagnostics.Level? = nil,
        traceID: OpalDiagnostics.TraceID? = nil,
        fields: [OpalDiagnostics.Field] = []
    ) {
        OpalDiagnostics.logger(category: category).record(
            event: event,
            level: level ?? defaultLevel(for: event),
            traceID: traceID,
            fields: fields
        )
    }

    static func publicField(_ name: String, _ value: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, publicValue: value)
    }

    static func publicField(_ name: String, _ value: Int) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value)
    }

    static func publicField(_ name: String, _ value: UInt64) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value)
    }

    static func publicField(_ name: String, _ value: Bool) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value)
    }

    static func privateField(_ name: String, _ value: String) -> OpalDiagnostics.Field {
        OpalDiagnostics.Field(name: name, value: value, privacy: .private)
    }

    static func operationField(_ operation: String) -> OpalDiagnostics.Field {
        publicField(Diagnostics.Fields.operation, operation)
    }

    static func moduleField(_ module: String = "opalbase") -> OpalDiagnostics.Field {
        publicField(Diagnostics.Fields.module, module)
    }

    static func accountIndexField(_ index: UInt32) -> OpalDiagnostics.Field {
        publicField(Diagnostics.Fields.accountIndex, UInt64(index))
    }

    static func usageField(_ usage: OpalBase.Key.DerivationPath.Usage) -> OpalDiagnostics.Field {
        publicField(Diagnostics.Fields.usage, usageDiagnosticsName(usage))
    }

    static func networkField(_ network: OpalBase.Network.Environment) -> OpalDiagnostics.Field {
        publicField(Diagnostics.Fields.network, networkDiagnosticsName(network))
    }

    static func errorCodeField(_ errorCode: String) -> OpalDiagnostics.Field {
        publicField(Diagnostics.Fields.errorCode, errorCode)
    }

    static func errorFields(
        for error: Swift.Error,
        fallback: String = OpalBase.Diagnostics.ErrorCodes.unknown
    ) -> [OpalDiagnostics.Field] {
        [
            errorCodeField(errorCode(for: error, fallback: fallback)),
            publicField(Diagnostics.Fields.errorType, String(describing: type(of: error)))
        ]
    }

    static func contextErrorFields(
        for error: Swift.Error,
        errorCode: String
    ) -> [OpalDiagnostics.Field] {
        [
            errorCodeField(errorCode),
            publicField(Diagnostics.Fields.errorType, String(describing: type(of: error)))
        ]
    }

    static func errorCode(
        for error: Swift.Error,
        fallback: String = OpalBase.Diagnostics.ErrorCodes.unknown
    ) -> String {
        if error is CancellationError {
            return Diagnostics.ErrorCodes.cancelled
        }

        if let walletError = error as? OpalBase.Wallet.Error {
            return errorCode(for: walletError)
        }

        if let accountError = error as? OpalBase.Account.Error {
            return errorCode(for: accountError, fallback: fallback)
        }

        if let networkError = error as? OpalBase.Network.Error {
            return errorCode(for: networkError)
        }

        if let fulcrumError = error as? SwiftFulcrum.Client.Error {
            return errorCode(for: fulcrumError)
        }

        if let claimableError = error as? OpalBase.Claimable.Error {
            return errorCode(for: claimableError, fallback: fallback)
        }

        return fallback
    }

    static func networkDiagnosticsFields(
        snapshot: OpalBase.Network.DiagnosticsSnapshot
    ) -> [OpalDiagnostics.Field] {
        [
            operationField("record_network_diagnostics_snapshot"),
            moduleField(),
            publicField(Diagnostics.Fields.reconnectionAttemptCount, snapshot.reconnectionAttemptCount),
            publicField(Diagnostics.Fields.reconnectSuccessCount, snapshot.reconnectSuccesses),
            publicField(Diagnostics.Fields.inflightUnaryCallCount, snapshot.inflightUnaryCallCount),
            publicField(Diagnostics.Fields.activeSubscriptionCount, snapshot.activeSubscriptionCount)
        ]
    }

    static func networkSubscriptionFields(
        subscriptions: [OpalBase.Network.DiagnosticsSubscription],
        operation: String
    ) -> [OpalDiagnostics.Field] {
        [
            operationField(operation),
            moduleField(),
            publicField(Diagnostics.Fields.activeSubscriptionCount, subscriptions.count)
        ]
    }

    static func usageDiagnosticsName(_ usage: OpalBase.Key.DerivationPath.Usage) -> String {
        switch usage {
        case .receiving:
            return "receiving"
        case .change:
            return "change"
        }
    }

    static func networkDiagnosticsName(_ network: OpalBase.Network.Environment) -> String {
        switch network {
        case .mainnet:
            return "mainnet"
        case .chipnet:
            return "chipnet"
        case .testnet:
            return "testnet"
        }
    }

    private static func defaultLevel(for event: OpalDiagnostics.Event) -> OpalDiagnostics.Level {
        if event.rawValue.hasSuffix(".failed") {
            return .error
        }
        if event.rawValue.hasSuffix(".started") || event.rawValue.hasSuffix(".succeeded") {
            return .debug
        }
        return .notice
    }

    private static func errorCode(for error: OpalBase.Wallet.Error) -> String {
        switch error {
        case .snapshotDoesNotMatchWallet:
            Diagnostics.ErrorCodes.storagePersistenceFailed
        case .accountAlreadyExists:
            Diagnostics.ErrorCodes.walletAccountAlreadyExists
        case .cannotFetchAccount:
            Diagnostics.ErrorCodes.walletAccountNotFound
        }
    }

    private static func errorCode(
        for error: OpalBase.Account.Error,
        fallback: String
    ) -> String {
        switch error {
        case .snapshotDoesNotMatchAccount:
            Diagnostics.ErrorCodes.accountSnapshotMismatch
        case .paymentHasNoRecipients,
             .paymentExceedsMaximumAmount,
             .paymentDoesNotSupportTokensUseTokenTransfer,
             .paymentCannotSpendTokenUTXOs,
             .tokenSendRequiresTokenAwareAddress,
             .tokenTransferHasNoRecipients,
             .tokenTransferRequiresSingleCategory,
             .tokenTransferInvalidTokenData,
             .tokenTransferInsufficientTokens,
             .tokenTransferInsufficientFunds,
             .tokenGenesisHasNoRecipients,
             .tokenGenesisRequiresTokenAwareAddress,
             .tokenGenesisNoEligibleGenesisInput,
             .tokenGenesisInvalidGenesisInput,
             .tokenGenesisRecipientHasNoTokenData,
             .tokenGenesisFungibleAmountIsZero,
             .tokenGenesisNonFungibleTokenCommitmentTooLong,
             .tokenMintHasNoRecipientsAndAuthorityReturnToWalletChange,
             .tokenMintRecipientHasNoTokenData,
             .tokenMintFungibleAmountIsZero,
             .tokenMintNonFungibleTokenCommitmentTooLong,
             .tokenMintNoEligibleMintingInput,
             .tokenMintInsufficientFungible,
             .tokenMintRequiresTokenAwareAddress,
             .tokenMutationInvalidAuthorityInput,
             .tokenMutationNoEligibleAuthorityInput,
             .tokenMutationNonFungibleTokenCommitmentTooLong,
             .tokenMutationRequiresTokenAwareAddress:
            Diagnostics.ErrorCodes.accountPaymentInvalid
        case .coinSelectionFailed(let error):
            if isInsufficientFundsError(error) {
                Diagnostics.ErrorCodes.accountInsufficientFunds
            } else {
                Diagnostics.ErrorCodes.accountCoinSelectionFailed
            }
        case .transactionBuildFailed,
             .tokenGenesisCannotComputeDustThreshold,
             .tokenGenesisTransactionBuildFailed,
             .tokenMutationCannotComputeDustThreshold:
            Diagnostics.ErrorCodes.accountTransactionBuildFailed
        case .broadcastFailed,
             .tokenGenesisBroadcastFailed,
             .tokenMintBroadcastFailed,
             .tokenMutationBroadcastFailed:
            Diagnostics.ErrorCodes.accountBroadcastFailed
        case .confirmationQueryFailed,
             .transactionConfirmationRefreshFailed:
            Diagnostics.ErrorCodes.accountConfirmationQueryFailed
        case .balanceFetchTimeout,
             .balanceRefreshFailed:
            Diagnostics.ErrorCodes.accountBalanceRefreshFailed
        case .transactionHistoryRefreshFailed:
            Diagnostics.ErrorCodes.accountTransactionHistoryRefreshFailed
        case .transactionDetailsRefreshFailed:
            Diagnostics.ErrorCodes.accountTransactionDetailsRefreshFailed
        case .feePreferenceUnavailable,
             .tokenSelectionFailed:
            fallback
        case .cashFusionHasNoSelectedInputs,
             .cashFusionHasNoOutputAmounts,
             .cashFusionCannotSpendTokenUTXOs,
             .cashFusionUnsupportedSelectedInputs,
             .cashFusionOutputAmountBelowMinimum:
            Diagnostics.ErrorCodes.cashFusionInvalidRequest
        case .cashFusionReservationFailed:
            Diagnostics.ErrorCodes.cashFusionReservationFailed
        case .cashFusionOutputReservationFailed:
            Diagnostics.ErrorCodes.cashFusionOutputReservationFailed
        }
    }

    private static func errorCode(for error: OpalBase.Network.Error) -> String {
        switch error.reason {
        case .transport, .network:
            Diagnostics.ErrorCodes.networkTransport
        case .server:
            Diagnostics.ErrorCodes.networkServer
        case .cancelled:
            Diagnostics.ErrorCodes.cancelled
        case .timeout:
            Diagnostics.ErrorCodes.networkTimeout
        case .protocolViolation:
            Diagnostics.ErrorCodes.networkProtocolViolation
        case .encoding:
            Diagnostics.ErrorCodes.networkEncoding
        case .decoding:
            Diagnostics.ErrorCodes.networkDecoding
        case .unknown:
            Diagnostics.ErrorCodes.unknown
        }
    }

    private static func errorCode(for error: SwiftFulcrum.Client.Error) -> String {
        switch error {
        case .transport:
            Diagnostics.ErrorCodes.networkTransport
        case .rpc:
            Diagnostics.ErrorCodes.networkServer
        case .coding(.encode):
            Diagnostics.ErrorCodes.networkEncoding
        case .coding(.decode):
            Diagnostics.ErrorCodes.networkDecoding
        case .client(let issue):
            errorCode(for: issue)
        }
    }

    private static func errorCode(for issue: SwiftFulcrum.Client.Error.ClientIssue) -> String {
        switch issue {
        case .cancelled:
            Diagnostics.ErrorCodes.cancelled
        case .timeout:
            Diagnostics.ErrorCodes.networkTimeout
        case .protocolMismatch,
             .invalidProtocolNegotiationRange,
             .emptyResponse:
            Diagnostics.ErrorCodes.networkProtocolViolation
        case .urlNotFound,
             .invalidURL,
             .duplicateHandler,
             .unknown:
            Diagnostics.ErrorCodes.networkTransport
        }
    }

    private static func isInsufficientFundsError(_ error: Swift.Error) -> Bool {
        if case OpalBase.Transaction.Error.insufficientFunds = error {
            return true
        }

        if case OpalBase.Address.Book.Error.insufficientFunds = error {
            return true
        }

        return false
    }

    private static func errorCode(
        for error: OpalBase.Claimable.Error,
        fallback: String
    ) -> String {
        switch error {
        case .invalidShareCodeFormat,
             .unsupportedShareCodeVersion,
             .invalidShareCodeNetwork,
             .emptyShareCodePayload,
             .invalidShareCodePayload:
            Diagnostics.ErrorCodes.claimableInvalidShareCode
        case .unsupportedVersion,
             .invalidNetworkTag,
             .invalidEnvelopeLength,
             .networkMismatch,
             .invalidClaimPrivateKey,
             .invalidRefundPrivateKey,
             .invalidClaimPublicKeyHash,
             .invalidRefundPublicKeyHash,
             .invalidExpiryBlockHeight,
             .invalidFundingReference,
             .invalidFundingOutput,
             .invalidDestinationOutput,
             .claimRequiresPreExpiry,
             .refundRequiresExpiry,
             .insufficientFundingValue,
             .dustOutput:
            fallback
        }
    }
}
