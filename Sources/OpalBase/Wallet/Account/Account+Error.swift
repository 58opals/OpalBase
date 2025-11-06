// Account+Error.swift

import Foundation

extension Account {
    public enum Error: Swift.Error {
        case snapshotDoesNotMatchAccount
        case balanceFetchTimeout(Address)
        case balanceRefreshFailed(Address, Swift.Error)
        case paymentHasNoRecipients
        case paymentExceedsMaximumAmount
        case coinSelectionFailed(Swift.Error)
        case transactionBuildFailed(Swift.Error)
        case broadcastFailed(Swift.Error)
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
            return leftAddress == rightAddress && leftError.localizedDescription == rightError.localizedDescription
        case (.coinSelectionFailed(let leftError), .coinSelectionFailed(let rightError)),
            (.transactionBuildFailed(let leftError), .transactionBuildFailed(let rightError)),
            (.broadcastFailed(let leftError), .broadcastFailed(let rightError)),
            (.feePreferenceUnavailable(let leftError), .feePreferenceUnavailable(let rightError)):
            return leftError.localizedDescription == rightError.localizedDescription
        default:
            return false
        }
    }
}

