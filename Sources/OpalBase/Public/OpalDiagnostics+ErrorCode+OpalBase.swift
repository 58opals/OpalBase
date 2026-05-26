// OpalDiagnostics+ErrorCode+OpalBase.swift

@preconcurrency public import OpalDiagnostics
import SwiftFulcrum

public extension OpalDiagnostics.ErrorCode {
    static let unknown = Self(rawValue: "unknown")
    static let cancelled = Self(rawValue: "cancelled")
    static let walletAccountAlreadyExists = Self(rawValue: "wallet.account_already_exists")
    static let walletAccountNotFound = Self(rawValue: "wallet.account_not_found")
    static let accountSnapshotMismatch = Self(rawValue: "account.snapshot_mismatch")
    static let accountPaymentInvalid = Self(rawValue: "account.payment_invalid")
    static let accountBalanceRefreshFailed = Self(rawValue: "account.balance_refresh_failed")
    static let accountInsufficientFunds = Self(rawValue: "account.insufficient_funds")
    static let accountCoinSelectionFailed = Self(rawValue: "account.coin_selection_failed")
    static let accountTransactionHistoryRefreshFailed = Self(rawValue: "account.transaction_history_refresh_failed")
    static let accountTransactionDetailsRefreshFailed = Self(rawValue: "account.transaction_details_refresh_failed")
    static let accountTransactionBuildFailed = Self(rawValue: "account.transaction_build_failed")
    static let accountBroadcastFailed = Self(rawValue: "account.broadcast_failed")
    static let accountConfirmationQueryFailed = Self(rawValue: "account.confirmation_query_failed")
    static let addressReservationFailed = Self(rawValue: "address.reservation_failed")
    static let networkTransport = Self(rawValue: "network.transport")
    static let networkServer = Self(rawValue: "network.server")
    static let networkTimeout = Self(rawValue: "network.timeout")
    static let networkEncoding = Self(rawValue: "network.encoding")
    static let networkDecoding = Self(rawValue: "network.decoding")
    static let networkProtocolViolation = Self(rawValue: "network.protocol_violation")
    static let cashFusionInvalidRequest = Self(rawValue: "cash_fusion.invalid_request")
    static let cashFusionReservationFailed = Self(rawValue: "cash_fusion.reservation_failed")
    static let cashFusionOutputReservationFailed = Self(rawValue: "cash_fusion.output_reservation_failed")
    static let cashFusionSessionFailed = Self(rawValue: "cash_fusion.session_failed")
    static let hedgeFundingFailed = Self(rawValue: "hedge.funding_failed")
    static let hedgeInvalid = Self(rawValue: "hedge.invalid")
    static let hedgeSettlementFailed = Self(rawValue: "hedge.settlement_failed")
    static let claimableInvalidEnvelope = Self(rawValue: "claimable.invalid_envelope")
    static let claimableInvalidShareCode = Self(rawValue: "claimable.invalid_share_code")
    static let claimableStatusFailed = Self(rawValue: "claimable.status_failed")
    static let transactionInvalid = Self(rawValue: "transaction.invalid")
    static let transactionInsufficientFunds = Self(rawValue: "transaction.insufficient_funds")
    static let transactionBuildFailed = Self(rawValue: "transaction.build_failed")
    static let transactionBroadcastFailed = Self(rawValue: "transaction.broadcast_failed")
    static let cashTokensInvalid = Self(rawValue: "cash_tokens.invalid")
    static let cashTokensBCMRFailed = Self(rawValue: "cash_tokens.bcmr_failed")
    static let cashTokensBCMRFetchFailed = Self(rawValue: "cash_tokens.bcmr_fetch_failed")
    static let keyInvalid = Self(rawValue: "key.invalid")
    static let encodingInvalid = Self(rawValue: "encoding.invalid")
    static let tokenMetadataSyncFailed = Self(rawValue: "token_metadata.sync_failed")
    static let storagePersistenceFailed = Self(rawValue: "storage.persistence_failed")

    static let all: [Self] = [
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
        hedgeFundingFailed, hedgeInvalid, hedgeSettlementFailed,
        claimableInvalidEnvelope, claimableInvalidShareCode, claimableStatusFailed,
        transactionInvalid, transactionInsufficientFunds, transactionBuildFailed,
        transactionBroadcastFailed,
        cashTokensInvalid, cashTokensBCMRFailed, cashTokensBCMRFetchFailed,
        keyInvalid, encodingInvalid,
        tokenMetadataSyncFailed, storagePersistenceFailed
    ]

    static func opalBaseCode(
        for error: Swift.Error,
        fallback: Self = .unknown
    ) -> Self {
        if error is CancellationError {
            return .cancelled
        }

        if let walletError = error as? OpalBase.Wallet.Error {
            return code(for: walletError)
        }

        if let accountError = error as? OpalBase.Account.Error {
            return code(for: accountError)
        }

        if let networkError = error as? OpalBase.Network.Error {
            return code(for: networkError)
        }

        if let fulcrumError = error as? SwiftFulcrum.Client.Error {
            return code(for: fulcrumError)
        }

        if let claimableError = error as? OpalBase.Claimable.Error {
            return code(for: claimableError)
        }

        if let storageError = error as? OpalBase.Storage.Error {
            return code(for: storageError)
        }

        if let storageSecurityError = error as? OpalBase.Storage.Security.Error {
            return code(for: storageSecurityError)
        }

        if let transactionError = error as? OpalBase.Transaction.Error {
            return code(for: transactionError)
        }

        if let cashTokensError = error as? OpalBase.CashTokens.Error {
            return code(for: cashTokensError)
        }

        if let bcmrClientError = error as? OpalBase.CashTokens.BCMR.Client.Error {
            return code(for: bcmrClientError)
        }

        if let bcmrFetcherError = error as? OpalBase.CashTokens.BCMR.Client.Fetcher.Error {
            return code(for: bcmrFetcherError)
        }

        if let hedgeError = error as? OpalBase.Hedge.Error {
            return code(for: hedgeError)
        }

        if let publicKeyError = error as? OpalBase.Key.PublicKey.Error {
            return code(for: publicKeyError)
        }

        if let derivationPathError = error as? OpalBase.Key.DerivationPath.Error {
            return code(for: derivationPathError)
        }

        if let mnemonicError = error as? OpalBase.Key.Mnemonic.Error {
            return code(for: mnemonicError)
        }

        if let encodingError = error as? OpalBase.Encoding.Error {
            return code(for: encodingError)
        }

        return fallback
    }
}

private extension OpalDiagnostics.ErrorCode {
    static func code(for error: OpalBase.Wallet.Error) -> Self {
        switch error {
        case .snapshotDoesNotMatchWallet:
            .storagePersistenceFailed
        case .accountAlreadyExists:
            .walletAccountAlreadyExists
        case .cannotFetchAccount:
            .walletAccountNotFound
        }
    }

    static func code(for error: OpalBase.Account.Error) -> Self {
        switch error {
        case .snapshotDoesNotMatchAccount:
            .accountSnapshotMismatch
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
            .accountPaymentInvalid
        case .coinSelectionFailed(let error):
            if isInsufficientFundsError(error) {
                .accountInsufficientFunds
            } else {
                .accountCoinSelectionFailed
            }
        case .transactionBuildFailed,
             .tokenGenesisCannotComputeDustThreshold,
             .tokenGenesisTransactionBuildFailed,
             .tokenMutationCannotComputeDustThreshold:
            .accountTransactionBuildFailed
        case .broadcastFailed,
             .tokenGenesisBroadcastFailed,
             .tokenMintBroadcastFailed,
             .tokenMutationBroadcastFailed:
            .accountBroadcastFailed
        case .confirmationQueryFailed,
             .transactionConfirmationRefreshFailed:
            .accountConfirmationQueryFailed
        case .balanceFetchTimeout,
             .balanceRefreshFailed:
            .accountBalanceRefreshFailed
        case .transactionHistoryRefreshFailed:
            .accountTransactionHistoryRefreshFailed
        case .transactionDetailsRefreshFailed:
            .accountTransactionDetailsRefreshFailed
        case .feePreferenceUnavailable:
            .accountTransactionBuildFailed
        case .tokenSelectionFailed:
            .accountCoinSelectionFailed
        case .cashFusionHasNoSelectedInputs,
             .cashFusionHasNoOutputAmounts,
             .cashFusionCannotSpendTokenUTXOs,
             .cashFusionUnsupportedSelectedInputs,
             .cashFusionOutputAmountBelowMinimum:
            .cashFusionInvalidRequest
        case .cashFusionReservationFailed:
            .cashFusionReservationFailed
        case .cashFusionOutputReservationFailed:
            .cashFusionOutputReservationFailed
        }
    }

    static func code(for error: OpalBase.Network.Error) -> Self {
        switch error.reason {
        case .transport, .network:
            .networkTransport
        case .server:
            .networkServer
        case .cancelled:
            .cancelled
        case .timeout:
            .networkTimeout
        case .protocolViolation:
            .networkProtocolViolation
        case .encoding:
            .networkEncoding
        case .decoding:
            .networkDecoding
        case .unknown:
            .unknown
        }
    }

    static func code(for error: SwiftFulcrum.Client.Error) -> Self {
        code(for: OpalBase.Network.FulcrumErrorTranslator.translate(error))
    }

    static func isInsufficientFundsError(_ error: Swift.Error) -> Bool {
        if case OpalBase.Transaction.Error.insufficientFunds = error {
            return true
        }

        if case OpalBase.Address.Book.Error.insufficientFunds = error {
            return true
        }

        return false
    }

    static func code(for error: OpalBase.Claimable.Error) -> Self {
        switch error {
        case .invalidShareCodeFormat,
             .unsupportedShareCodeVersion,
             .invalidShareCodeNetwork,
             .emptyShareCodePayload,
             .invalidShareCodePayload:
            .claimableInvalidShareCode
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
            .claimableInvalidEnvelope
        }
    }

    static func code(for error: OpalBase.Storage.Error) -> Self {
        switch error {
        case .persistenceUnavailable,
             .persistenceFailure,
             .encodingFailure,
             .decodingFailure,
             .secureStoreFailure,
             .missingAccountIdentifier:
            .storagePersistenceFailed
        }
    }

    static func code(for error: OpalBase.Storage.Security.Error) -> Self {
        switch error {
        case .protectionUnavailable,
             .insufficientProtection,
             .encryptionFailure,
             .decryptionFailure:
            .storagePersistenceFailed
        }
    }

    static func code(for error: OpalBase.Transaction.Error) -> Self {
        switch error {
        case .insufficientFunds:
            .transactionInsufficientFunds
        case .cannotBroadcastTransaction:
            .transactionBroadcastFailed
        case .cannotCreateTransaction,
             .feeCalculationOverflow:
            .transactionBuildFailed
        case .accountNotFound,
             .unsupportedHashType,
             .unsupportedSignatureFormat,
             .outputValueIsLessThanTheDustLimit,
             .sighashSingleIndexOutOfRange,
             .missingUnspentTransactionOutputs,
             .unspentTransactionOutputsCountMismatch,
             .invalidTransactionHashLength,
             .transactionNotFound:
            .transactionInvalid
        }
    }

    static func code(for error: OpalBase.CashTokens.Error) -> Self {
        switch error {
        case .invalidHexadecimalString,
             .categoryIdentifierLengthMismatch,
             .commitmentLengthOutOfRange,
             .invalidFungibleAmountString,
             .invalidTokenPrefix,
             .invalidTokenPrefixLength,
             .invalidTokenPrefixBitfield,
             .invalidTokenPrefixCompactSize,
             .invalidTokenPrefixCommitmentLength,
             .invalidTokenPrefixFungibleAmount,
             .invalidTokenPrefixCapability:
            .cashTokensInvalid
        }
    }

    static func code(for error: OpalBase.CashTokens.BCMR.Client.Error) -> Self {
        switch error {
        case .registryDecodingFailed,
             .invalidRegistryIdentity:
            .cashTokensBCMRFailed
        }
    }

    static func code(for error: OpalBase.CashTokens.BCMR.Client.Fetcher.Error) -> Self {
        switch error {
        case .invalidResourceIdentifier,
             .unsupportedScheme,
             .missingInterPlanetaryFileSystemGateway,
             .invalidInterPlanetaryFileSystemGateway,
             .missingRedirectLocation,
             .permanentRedirect,
             .responseTooLarge,
             .unexpectedResponseStatus,
             .invalidMaximumBytes:
            .cashTokensBCMRFetchFailed
        }
    }

    static func code(for error: OpalBase.Hedge.Error) -> Self {
        switch error {
        case .unsupportedWalletSide,
             .unsupportedCounterpartySide,
             .networkMismatch,
             .invalidFundingAmount,
             .invalidFundingOutputIndex,
             .invalidTransactionHash,
             .oraclePublicKeyMismatch,
             .fundingOutputNotFound,
             .fundingOutputAmbiguous:
            .hedgeInvalid
        }
    }

    static func code(for error: OpalBase.Key.PublicKey.Error) -> Self {
        switch error {
        case .invalidFormat,
             .invalidLength,
             .invalidVersion,
             .invalidChecksum,
             .hardenedDerivation,
             .publicKeyDerivationFailed,
             .derivationPathTooShort:
            .keyInvalid
        }
    }

    static func code(for error: OpalBase.Key.DerivationPath.Error) -> Self {
        switch error {
        case .indexOverflow,
             .indexTooLargeForHardening,
             .indexTooSmallForUnhardening:
            .keyInvalid
        }
    }

    static func code(for error: OpalBase.Key.Mnemonic.Error) -> Self {
        switch error {
        case .invalidWordCount,
             .invalidEntropyLength,
             .invalidWord,
             .invalidChecksum,
             .ambiguousLanguage,
             .randomGenerationFailed,
             .wordListResourceMissing,
             .invalidWordList:
            .keyInvalid
        }
    }

    static func code(for error: OpalBase.Encoding.Error) -> Self {
        switch error {
        case .invalidHexadecimalString:
            .encodingInvalid
        }
    }
}
