// Address+Book+Error.swift

import Foundation

extension Address.Book {
    enum Error: Swift.Error, Sendable {
        case indexOutOfBounds
        
        case privateKeyNotFound
        case addressNotFound
        case entryNotFound
        
        case privateKeyDuplicated(PrivateKey)
        case addressDuplicated(Address)
        case entryDuplicated(Address.Book.Entry)
        
        case insufficientFunds
        case paymentExceedsMaximumAmount
        
        case cacheInvalid
        case cacheUpdateFailed
        case invalidSnapshotBalance(value: UInt64, reason: Swift.Error)
        case transactionHistoryRefreshFailed(Address, Swift.Error)
        case transactionConfirmationRefreshFailed(Transaction.Hash, Swift.Error)
    }
}

extension Address.Book.Error: Equatable {
    static func == (lhs: Address.Book.Error, rhs: Address.Book.Error) -> Bool {
        switch (lhs, rhs) {
        case (.indexOutOfBounds, .indexOutOfBounds),
            (.privateKeyNotFound, .privateKeyNotFound),
            (.addressNotFound, .addressNotFound),
            (.entryNotFound, .entryNotFound),
            (.insufficientFunds, .insufficientFunds),
            (.paymentExceedsMaximumAmount, .paymentExceedsMaximumAmount),
            (.cacheInvalid, .cacheInvalid),
            (.cacheUpdateFailed, .cacheUpdateFailed):
            return true
        case (.privateKeyDuplicated(let leftPrivateKey), .privateKeyDuplicated(let rightPrivateKey)):
            return leftPrivateKey == rightPrivateKey
        case (.addressDuplicated(let leftAddress), .addressDuplicated(let rightAddress)):
            return leftAddress == rightAddress
        case (.entryDuplicated(let leftEntry), .entryDuplicated(let rightEntry)):
            return leftEntry == rightEntry
        case (.invalidSnapshotBalance(let leftValue, let leftError),
              .invalidSnapshotBalance(let rightValue, let rightError)):
            return leftValue == rightValue && leftError.localizedDescription == rightError.localizedDescription
        case (.transactionHistoryRefreshFailed(let leftAddress, let leftError),
              .transactionHistoryRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && leftError.localizedDescription == rightError.localizedDescription
        case (.transactionConfirmationRefreshFailed(let leftHash, let leftError),
              .transactionConfirmationRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && leftError.localizedDescription == rightError.localizedDescription
        default:
            return false
        }
    }
}
