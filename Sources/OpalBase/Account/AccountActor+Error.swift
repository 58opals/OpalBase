// AccountActor+Error.swift

import Foundation

extension AccountActor {
    public enum Error: Swift.Error {
        case snapshotDoesNotMatchAccount
        case balanceFetchTimeout(AddressModel)
        case balanceRefreshFailed(AddressModel, Swift.Error)
        case transactionHistoryRefreshFailed(AddressModel, Swift.Error)
        case transactionDetailsRefreshFailed(TransactionModel.HashModel, Swift.Error)
        case transactionConfirmationRefreshFailed(TransactionModel.HashModel, Swift.Error)
        case paymentHasNoRecipients
        case paymentExceedsMaximumAmount
        case paymentDoesNotSupportTokensUseTokenTransfer
        case paymentCannotSpendTokenUTXOs
        case tokenSendRequiresTokenAwareAddress([AddressModel])
        case tokenTransferHasNoRecipients
        case tokenTransferRequiresSingleCategory
        case tokenTransferInsufficientTokens
        case tokenTransferInsufficientFunds(required: UInt64)
        case tokenSelectionFailed(Swift.Error)
        case tokenGenesisHasNoRecipients
        case tokenGenesisRequiresTokenAwareAddress([AddressModel])
        case tokenGenesisNoEligibleGenesisInput
        case tokenGenesisInvalidGenesisInput
        case tokenGenesisCannotComputeDustThreshold(Swift.Error)
        case tokenGenesisTransactionBuildFailed(Swift.Error)
        case tokenGenesisBroadcastFailed(Swift.Error)
        case tokenGenesisFungibleAmountIsZero
        case tokenGenesisNonFungibleTokenCommitmentTooLong(maximum: Int, actual: Int)
        case tokenMintHasNoRecipientsAndAuthorityReturnToWalletChange
        case tokenMintRecipientHasNoTokenData
        case tokenMintFungibleAmountIsZero
        case tokenMintNonFungibleTokenCommitmentTooLong(maximum: Int, actual: Int)
        case tokenMintNoEligibleMintingInput
        case tokenMintInsufficientFungible
        case tokenMintRequiresTokenAwareAddress([AddressModel])
        case tokenMintBroadcastFailed(Swift.Error)
        case tokenMutationInvalidAuthorityInput
        case tokenMutationNoEligibleAuthorityInput
        case tokenMutationNonFungibleTokenCommitmentTooLong(maximum: Int, actual: Int)
        case tokenMutationRequiresTokenAwareAddress([AddressModel])
        case tokenMutationCannotComputeDustThreshold(Swift.Error)
        case tokenMutationBroadcastFailed(Swift.Error)
        case coinSelectionFailed(Swift.Error)
        case transactionBuildFailed(Swift.Error)
        case broadcastFailed(Swift.Error)
        case confirmationQueryFailed(Swift.Error)
        case feePreferenceUnavailable(Swift.Error)
    }
}

extension AccountActor.Error: Equatable {
    public static func == (lhs: AccountActor.Error, rhs: AccountActor.Error) -> Bool {
        switch (lhs, rhs) {
        case (.snapshotDoesNotMatchAccount, .snapshotDoesNotMatchAccount),
            (.paymentHasNoRecipients, .paymentHasNoRecipients),
            (.paymentExceedsMaximumAmount, .paymentExceedsMaximumAmount),
            (.paymentDoesNotSupportTokensUseTokenTransfer, .paymentDoesNotSupportTokensUseTokenTransfer),
            (.paymentCannotSpendTokenUTXOs, .paymentCannotSpendTokenUTXOs):
            return true
        case (.tokenSendRequiresTokenAwareAddress(let leftAddresses),
              .tokenSendRequiresTokenAwareAddress(let rightAddresses)):
            return leftAddresses == rightAddresses
        case (.tokenTransferHasNoRecipients, .tokenTransferHasNoRecipients),
            (.tokenTransferRequiresSingleCategory, .tokenTransferRequiresSingleCategory),
            (.tokenTransferInsufficientTokens, .tokenTransferInsufficientTokens),
            (.tokenGenesisHasNoRecipients, .tokenGenesisHasNoRecipients),
            (.tokenGenesisNoEligibleGenesisInput, .tokenGenesisNoEligibleGenesisInput),
            (.tokenGenesisInvalidGenesisInput, .tokenGenesisInvalidGenesisInput),
            (.tokenGenesisFungibleAmountIsZero, .tokenGenesisFungibleAmountIsZero),
            (.tokenMintHasNoRecipientsAndAuthorityReturnToWalletChange,
             .tokenMintHasNoRecipientsAndAuthorityReturnToWalletChange),
            (.tokenMintRecipientHasNoTokenData, .tokenMintRecipientHasNoTokenData),
            (.tokenMintFungibleAmountIsZero, .tokenMintFungibleAmountIsZero),
            (.tokenMintNoEligibleMintingInput, .tokenMintNoEligibleMintingInput),
            (.tokenMintInsufficientFungible, .tokenMintInsufficientFungible),
            (.tokenMutationInvalidAuthorityInput, .tokenMutationInvalidAuthorityInput),
            (.tokenMutationNoEligibleAuthorityInput, .tokenMutationNoEligibleAuthorityInput):
            return true
        case (.tokenGenesisRequiresTokenAwareAddress(let leftAddresses),
              .tokenGenesisRequiresTokenAwareAddress(let rightAddresses)):
            return leftAddresses == rightAddresses
        case (.tokenMintRequiresTokenAwareAddress(let leftAddresses),
              .tokenMintRequiresTokenAwareAddress(let rightAddresses)):
            return leftAddresses == rightAddresses
        case (.tokenMutationRequiresTokenAwareAddress(let leftAddresses),
              .tokenMutationRequiresTokenAwareAddress(let rightAddresses)):
            return leftAddresses == rightAddresses
        case (.tokenTransferInsufficientFunds(let leftRequired), .tokenTransferInsufficientFunds(let rightRequired)):
            return leftRequired == rightRequired
        case (.tokenGenesisNonFungibleTokenCommitmentTooLong(let leftMaximum, let leftActual),
              .tokenGenesisNonFungibleTokenCommitmentTooLong(let rightMaximum, let rightActual)):
            return leftMaximum == rightMaximum && leftActual == rightActual
        case (.tokenMintNonFungibleTokenCommitmentTooLong(let leftMaximum, let leftActual),
              .tokenMintNonFungibleTokenCommitmentTooLong(let rightMaximum, let rightActual)):
            return leftMaximum == rightMaximum && leftActual == rightActual
        case (.tokenMutationNonFungibleTokenCommitmentTooLong(let leftMaximum, let leftActual),
              .tokenMutationNonFungibleTokenCommitmentTooLong(let rightMaximum, let rightActual)):
            return leftMaximum == rightMaximum && leftActual == rightActual
        case (.tokenSelectionFailed(let leftError), .tokenSelectionFailed(let rightError)):
            return NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.balanceFetchTimeout(let leftAddress), .balanceFetchTimeout(let rightAddress)):
            return leftAddress == rightAddress
        case (.balanceRefreshFailed(let leftAddress, let leftError),
              .balanceRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.transactionHistoryRefreshFailed(let leftAddress, let leftError),
              .transactionHistoryRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.transactionDetailsRefreshFailed(let leftHash, let leftError),
              .transactionDetailsRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.transactionConfirmationRefreshFailed(let leftHash, let leftError),
              .transactionConfirmationRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.coinSelectionFailed(let leftError), .coinSelectionFailed(let rightError)),
            (.tokenGenesisCannotComputeDustThreshold(let leftError), .tokenGenesisCannotComputeDustThreshold(let rightError)),
            (.tokenGenesisTransactionBuildFailed(let leftError), .tokenGenesisTransactionBuildFailed(let rightError)),
            (.tokenGenesisBroadcastFailed(let leftError), .tokenGenesisBroadcastFailed(let rightError)),
            (.tokenMintBroadcastFailed(let leftError), .tokenMintBroadcastFailed(let rightError)),
            (.tokenMutationCannotComputeDustThreshold(let leftError), .tokenMutationCannotComputeDustThreshold(let rightError)),
            (.tokenMutationBroadcastFailed(let leftError), .tokenMutationBroadcastFailed(let rightError)),
            (.transactionBuildFailed(let leftError), .transactionBuildFailed(let rightError)),
            (.broadcastFailed(let leftError), .broadcastFailed(let rightError)),
            (.confirmationQueryFailed(let leftError), .confirmationQueryFailed(let rightError)),
            (.feePreferenceUnavailable(let leftError), .feePreferenceUnavailable(let rightError)):
            return NetworkModel.checkFailureEquivalence(leftError, rightError)
        default:
            return false
        }
    }
}

extension AccountActor {
    static func makeAccountError(from error: AddressModel.BookActor.Error) -> Swift.Error {
        switch error {
        case .cacheUpdateFailed(let address, let underlying):
            return Error.balanceRefreshFailed(address, underlying)
        case .transactionHistoryRefreshFailed(let address, let underlying):
            return Error.transactionHistoryRefreshFailed(address, underlying)
        case .transactionDetailsRefreshFailed(let hash, let underlying):
            return Error.transactionDetailsRefreshFailed(hash, underlying)
        case .transactionConfirmationRefreshFailed(let hash, let underlying):
            return Error.transactionConfirmationRefreshFailed(hash, underlying)
        default:
            return error
        }
    }
}

extension AccountActor {
    func mapAddressBookError<T>(_ work: () async throws -> T) async throws -> T {
        do {
            return try await work()
        } catch let error as AddressModel.BookActor.Error {
            throw Self.makeAccountError(from: error)
        }
    }
}
