// OpalBase+Address+Book+Error.swift

import Foundation

extension _OpalBase.Address.Book {
    enum Error: Swift.Error, Sendable {
        case indexOutOfBounds
        
        case privateKeyNotFound
        case addressNotFound
        case entryNotFound
        
        case privateKeyDuplicated(Data)
        case addressDuplicated(OpalBase.Address)
        case entryDuplicated(OpalBase.Address.Book.Entry)
        case entryAlreadyReserved(OpalBase.Address.Book.Entry)
        
        case insufficientFunds
        case paymentExceedsMaximumAmount
        
        case utxoNotFound
        case utxoAlreadyReserved(OpalBase.Transaction.Output.Unspent)
        
        case cacheInvalid
        case cacheUpdateFailed(OpalBase.Address, Swift.Error)
        case invalidSnapshotBalance(value: UInt64, reason: Swift.Error)
        case invalidSnapshotTokenData(reason: Swift.Error)
        case transactionHistoryRefreshFailed(OpalBase.Address, Swift.Error)
        case transactionDetailsRefreshFailed(OpalBase.Transaction.Hash, Swift.Error)
        case transactionConfirmationRefreshFailed(OpalBase.Transaction.Hash, Swift.Error)
    }
}

extension _OpalBase.Address.Book.Error: Equatable {
    static func == (lhs: OpalBase.Address.Book.Error, rhs: OpalBase.Address.Book.Error) -> Bool {
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
            return leftAddress == rightAddress && OpalBase.Network.checkFailureEquivalence(leftError, rightError)
        case (.invalidSnapshotBalance(let leftValue, let leftError),
              .invalidSnapshotBalance(let rightValue, let rightError)):
            return leftValue == rightValue && OpalBase.Network.checkFailureEquivalence(leftError, rightError)
        case (.invalidSnapshotTokenData(let leftError),
              .invalidSnapshotTokenData(let rightError)):
            return OpalBase.Network.checkFailureEquivalence(leftError, rightError)
        case (.transactionHistoryRefreshFailed(let leftAddress, let leftError),
              .transactionHistoryRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && OpalBase.Network.checkFailureEquivalence(leftError, rightError)
        case (.transactionDetailsRefreshFailed(let leftHash, let leftError),
              .transactionDetailsRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && OpalBase.Network.checkFailureEquivalence(leftError, rightError)
        case (.transactionConfirmationRefreshFailed(let leftHash, let leftError),
              .transactionConfirmationRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && OpalBase.Network.checkFailureEquivalence(leftError, rightError)
        default:
            return false
        }
    }
}
