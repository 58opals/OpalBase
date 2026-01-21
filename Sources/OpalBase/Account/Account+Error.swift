// Account+Error.swift

import Foundation

extension Account {
    public enum Error: Swift.Error {
        case snapshotDoesNotMatchAccount
        case balanceFetchTimeout(Address)
        case balanceRefreshFailed(Address, Swift.Error)
        case transactionHistoryRefreshFailed(Address, Swift.Error)
        case transactionConfirmationRefreshFailed(Transaction.Hash, Swift.Error)
        case paymentHasNoRecipients
        case paymentExceedsMaximumAmount
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
        case (.balanceFetchTimeout(let leftAddress), .balanceFetchTimeout(let rightAddress)):
            return leftAddress == rightAddress
        case (.balanceRefreshFailed(let leftAddress, let leftError),
              .balanceRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && Network.FulcrumErrorTranslator.isFailureEquivalent(leftError, rightError)
        case (.transactionHistoryRefreshFailed(let leftAddress, let leftError),
              .transactionHistoryRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && Network.FulcrumErrorTranslator.isFailureEquivalent(leftError, rightError)
        case (.transactionConfirmationRefreshFailed(let leftHash, let leftError),
              .transactionConfirmationRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && Network.FulcrumErrorTranslator.isFailureEquivalent(leftError, rightError)
        case (.coinSelectionFailed(let leftError), .coinSelectionFailed(let rightError)),
            (.transactionBuildFailed(let leftError), .transactionBuildFailed(let rightError)),
            (.broadcastFailed(let leftError), .broadcastFailed(let rightError)),
            (.confirmationQueryFailed(let leftError), .confirmationQueryFailed(let rightError)),
            (.feePreferenceUnavailable(let leftError), .feePreferenceUnavailable(let rightError)):
            return Network.FulcrumErrorTranslator.isFailureEquivalent(leftError, rightError)
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
        case .transactionConfirmationRefreshFailed(let hash, let underlying):
            return Error.transactionConfirmationRefreshFailed(hash, underlying)
        default:
            return error
        }
    }
}
