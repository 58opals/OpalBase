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
        case entryAlreadyReserved(Address.Book.Entry)
        
        case insufficientFunds
        case paymentExceedsMaximumAmount
        
        case utxoNotFound
        case utxoAlreadyReserved(Transaction.Output.Unspent)
        
        case cacheInvalid
        case cacheUpdateFailed(Address, Swift.Error)
        case invalidSnapshotBalance(value: UInt64, reason: Swift.Error)
        case invalidSnapshotTokenData(reason: Swift.Error)
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
            (.utxoNotFound, .utxoNotFound),
            (.cacheInvalid, .cacheInvalid):
            return true
        case (.privateKeyDuplicated(let leftPrivateKey), .privateKeyDuplicated(let rightPrivateKey)):
            return leftPrivateKey == rightPrivateKey
        case (.addressDuplicated(let leftAddress), .addressDuplicated(let rightAddress)):
            return leftAddress == rightAddress
        case (.entryDuplicated(let leftEntry), .entryDuplicated(let rightEntry)),
            (.entryAlreadyReserved(let leftEntry), .entryAlreadyReserved(let rightEntry)):
            return leftEntry == rightEntry
        case (.utxoAlreadyReserved(let leftUTXO), .utxoAlreadyReserved(let rightUTXO)):
            return leftUTXO == rightUTXO
        case (.cacheUpdateFailed(let leftAddress, let leftError),
              .cacheUpdateFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && Network.checkFailureEquivalence(leftError, rightError)
        case (.invalidSnapshotBalance(let leftValue, let leftError),
              .invalidSnapshotBalance(let rightValue, let rightError)):
            return leftValue == rightValue && Network.checkFailureEquivalence(leftError, rightError)
        case (.invalidSnapshotTokenData(let leftError),
              .invalidSnapshotTokenData(let rightError)):
            return Network.checkFailureEquivalence(leftError, rightError)
        case (.transactionHistoryRefreshFailed(let leftAddress, let leftError),
              .transactionHistoryRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && Network.checkFailureEquivalence(leftError, rightError)
        case (.transactionConfirmationRefreshFailed(let leftHash, let leftError),
              .transactionConfirmationRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && Network.checkFailureEquivalence(leftError, rightError)
        default:
            return false
        }
    }
}
