// AddressModel+BookActor+Error.swift

import Foundation

extension AddressModel.BookActor {
    enum Error: Swift.Error, Sendable {
        case indexOutOfBounds
        
        case privateKeyNotFound
        case addressNotFound
        case entryNotFound
        
        case privateKeyDuplicated(PrivateKeyModel)
        case addressDuplicated(AddressModel)
        case entryDuplicated(AddressModel.BookActor.EntryModel)
        case entryAlreadyReserved(AddressModel.BookActor.EntryModel)
        
        case insufficientFunds
        case paymentExceedsMaximumAmount
        
        case utxoNotFound
        case utxoAlreadyReserved(TransactionModel.OutputModel.UnspentModel)
        
        case cacheInvalid
        case cacheUpdateFailed(AddressModel, Swift.Error)
        case invalidSnapshotBalance(value: UInt64, reason: Swift.Error)
        case invalidSnapshotTokenData(reason: Swift.Error)
        case transactionHistoryRefreshFailed(AddressModel, Swift.Error)
        case transactionDetailsRefreshFailed(TransactionModel.HashModel, Swift.Error)
        case transactionConfirmationRefreshFailed(TransactionModel.HashModel, Swift.Error)
    }
}

extension AddressModel.BookActor.Error: Equatable {
    static func == (lhs: AddressModel.BookActor.Error, rhs: AddressModel.BookActor.Error) -> Bool {
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
            return leftAddress == rightAddress && NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.invalidSnapshotBalance(let leftValue, let leftError),
              .invalidSnapshotBalance(let rightValue, let rightError)):
            return leftValue == rightValue && NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.invalidSnapshotTokenData(let leftError),
              .invalidSnapshotTokenData(let rightError)):
            return NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.transactionHistoryRefreshFailed(let leftAddress, let leftError),
              .transactionHistoryRefreshFailed(let rightAddress, let rightError)):
            return leftAddress == rightAddress && NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.transactionDetailsRefreshFailed(let leftHash, let leftError),
              .transactionDetailsRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && NetworkModel.checkFailureEquivalence(leftError, rightError)
        case (.transactionConfirmationRefreshFailed(let leftHash, let leftError),
              .transactionConfirmationRefreshFailed(let rightHash, let rightError)):
            return leftHash == rightHash && NetworkModel.checkFailureEquivalence(leftError, rightError)
        default:
            return false
        }
    }
}
