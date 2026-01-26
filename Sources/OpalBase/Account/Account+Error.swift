// Account+Error.swift

import Foundation

extension Account {
    public enum Error: Swift.Error {
        case snapshotDoesNotMatchAccount
        case balanceFetchTimeout(Address)
        case balanceRefreshFailed(Address, Swift.Error)
        case transactionHistoryRefreshFailed(Address, Swift.Error)
        case transactionDetailsRefreshFailed(Transaction.Hash, Swift.Error)
        case transactionConfirmationRefreshFailed(Transaction.Hash, Swift.Error)
        case paymentHasNoRecipients
        case paymentExceedsMaximumAmount
        case tokenSendRequiresTokenAwareAddress([Address])
        case tokenTransferHasNoRecipients
        case tokenTransferRequiresSingleCategory
        case tokenTransferInsufficientTokens
        case tokenTransferInsufficientFunds(required: UInt64)
        case tokenSelectionFailed(Swift.Error)
        case tokenGenesisFungibleAmountIsZero
        case tokenGenesisNonFungibleTokenCommitmentTooLong(maximum: Int, actual: Int)
        case coinSelectionFailed(Swift.Error)
        case transactionBuildFailed(Swift.Error)
        case broadcastFailed(Swift.Error)
        case confirmationQueryFailed(Swift.Error)
        case feePreferenceUnavailable(Swift.Error)
    }
}

extension Account.Error: Equatable {
    public static func == (lhs: Account.Error, rhs: Account.Error) -> Bool {
        switch (lhs, rhs) {
        case (.snapshotDoesNotMatchAccount, .snapshotDoesNotMatchAccount),
            (.paymentHasNoRecipients, .paymentHasNoRecipients),
            (.paymentExceedsMaximumAmount, .paymentExceedsMaximumAmount):
            return true
        case (.tokenSendRequiresTokenAwareAddress(let leftAddresses),
              .tokenSendRequiresTokenAwareAddress(let rightAddresses)):
            return leftAddresses == rightAddresses
        case (.tokenTransferHasNoRecipients, .tokenTransferHasNoRecipients),
            (.tokenTransferRequiresSingleCategory, .tokenTransferRequiresSingleCategory),
            (.tokenTransferInsufficientTokens, .tokenTransferInsufficientTokens),
            (.tokenGenesisFungibleAmountIsZero, .tokenGenesisFungibleAmountIsZero):
            return true
        case (.tokenTransferInsufficientFunds(let leftRequired), .tokenTransferInsufficientFunds(let rightRequired)):
            return leftRequired == rightRequired
        case (.tokenGenesisNonFungibleTokenCommitmentTooLong(let leftMaximum, let leftActual),
              .tokenGenesisNonFungibleTokenCommitmentTooLong(let rightMaximum, let rightActual)):
            return leftMaximum == rightMaximum && leftActual == rightActual
        case (.tokenSelectionFailed(let leftError), .tokenSelectionFailed(let rightError)):
            return Network.checkFailureEquivalence(leftError, rightError)
        case (.balanceFetchTimeout(let leftAddress), .balanceFetchTimeout(let rightAddress)):
            return leftAddress == rightAddress
        case (.balanceRefreshFailed(let leftAddress, let leftError),
              .balanceRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && Network.checkFailureEquivalence(leftError, rightError)
        case (.transactionHistoryRefreshFailed(let leftAddress, let leftError),
              .transactionHistoryRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && Network.checkFailureEquivalence(leftError, rightError)
        case (.transactionDetailsRefreshFailed(let leftHash, let leftError),
              .transactionDetailsRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && Network.checkFailureEquivalence(leftError, rightError)
        case (.transactionConfirmationRefreshFailed(let leftHash, let leftError),
              .transactionConfirmationRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && Network.checkFailureEquivalence(leftError, rightError)
        case (.coinSelectionFailed(let leftError), .coinSelectionFailed(let rightError)),
            (.transactionBuildFailed(let leftError), .transactionBuildFailed(let rightError)),
            (.broadcastFailed(let leftError), .broadcastFailed(let rightError)),
            (.confirmationQueryFailed(let leftError), .confirmationQueryFailed(let rightError)),
            (.feePreferenceUnavailable(let leftError), .feePreferenceUnavailable(let rightError)):
            return Network.checkFailureEquivalence(leftError, rightError)
        default:
            return false
        }
    }
}

extension Account {
    static func makeAccountError(from error: Address.Book.Error) -> Swift.Error {
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
