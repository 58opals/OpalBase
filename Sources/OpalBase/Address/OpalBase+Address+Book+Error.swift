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
        case invalidSnapshotFee(value: UInt64, reason: Swift.Error)
        case invalidSnapshotEntryUsage(
            expected: OpalBase.Key.DerivationPath.Usage,
            actual: OpalBase.Key.DerivationPath.Usage,
            index: UInt32
        )
        case invalidSnapshotEntryReservationState(
            usage: OpalBase.Key.DerivationPath.Usage,
            index: UInt32
        )
        case invalidSnapshotDuplicateEntry(
            usage: OpalBase.Key.DerivationPath.Usage,
            index: UInt32
        )
        case invalidSnapshotDuplicateUTXO(
            transactionHash: OpalBase.Transaction.Hash,
            outputIndex: UInt32
        )
        case invalidSnapshotUTXOLockingScript(Data)
        case invalidSnapshotDuplicateTransaction(OpalBase.Transaction.Hash)
        case invalidSnapshotTransactionHashLength(expected: Int, actual: Int)
        case invalidSnapshotScriptHashLength(expected: Int, actual: Int)
        case invalidSnapshotMissingScriptHashes
        case invalidSnapshotDuplicateScriptHash(String)
        case invalidSnapshotTransactionScriptHash(String)
        case invalidSnapshotMerkleProofHashLength(expected: Int, actual: Int)
        case invalidSnapshotTokenData(reason: Swift.Error)
        case invalidSnapshotDuplicateTokenDelta(OpalBase.CashTokens.TokenData)
        case invalidSnapshotVerificationState
        case invalidSnapshotConfirmationState
        case tokenDeltaOverflow
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
            (.tokenDeltaOverflow, .tokenDeltaOverflow),
            (.invalidSnapshotVerificationState, .invalidSnapshotVerificationState),
            (.invalidSnapshotConfirmationState, .invalidSnapshotConfirmationState),
            (.invalidSnapshotMissingScriptHashes, .invalidSnapshotMissingScriptHashes),
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
        case (.invalidSnapshotFee(let leftValue, let leftError),
              .invalidSnapshotFee(let rightValue, let rightError)):
            return leftValue == rightValue && OpalBase.Network.checkFailureEquivalence(leftError, rightError)
        case (.invalidSnapshotEntryUsage(let leftExpected, let leftActual, let leftIndex),
              .invalidSnapshotEntryUsage(let rightExpected, let rightActual, let rightIndex)):
            return leftExpected == rightExpected && leftActual == rightActual && leftIndex == rightIndex
        case (.invalidSnapshotEntryReservationState(let leftUsage, let leftIndex),
              .invalidSnapshotEntryReservationState(let rightUsage, let rightIndex)):
            return leftUsage == rightUsage && leftIndex == rightIndex
        case (.invalidSnapshotDuplicateEntry(let leftUsage, let leftIndex),
              .invalidSnapshotDuplicateEntry(let rightUsage, let rightIndex)):
            return leftUsage == rightUsage && leftIndex == rightIndex
        case (.invalidSnapshotDuplicateUTXO(let leftHash, let leftIndex),
              .invalidSnapshotDuplicateUTXO(let rightHash, let rightIndex)):
            return leftHash == rightHash && leftIndex == rightIndex
        case (.invalidSnapshotUTXOLockingScript(let leftLockingScript),
              .invalidSnapshotUTXOLockingScript(let rightLockingScript)):
            return leftLockingScript == rightLockingScript
        case (.invalidSnapshotDuplicateTransaction(let leftHash),
              .invalidSnapshotDuplicateTransaction(let rightHash)):
            return leftHash == rightHash
        case (.invalidSnapshotTransactionHashLength(let leftExpected, let leftActual),
              .invalidSnapshotTransactionHashLength(let rightExpected, let rightActual)):
            return leftExpected == rightExpected && leftActual == rightActual
        case (.invalidSnapshotScriptHashLength(let leftExpected, let leftActual),
              .invalidSnapshotScriptHashLength(let rightExpected, let rightActual)):
            return leftExpected == rightExpected && leftActual == rightActual
        case (.invalidSnapshotDuplicateScriptHash(let leftScriptHash),
              .invalidSnapshotDuplicateScriptHash(let rightScriptHash)):
            return leftScriptHash == rightScriptHash
        case (.invalidSnapshotTransactionScriptHash(let leftScriptHash),
              .invalidSnapshotTransactionScriptHash(let rightScriptHash)):
            return leftScriptHash == rightScriptHash
        case (.invalidSnapshotMerkleProofHashLength(let leftExpected, let leftActual),
              .invalidSnapshotMerkleProofHashLength(let rightExpected, let rightActual)):
            return leftExpected == rightExpected && leftActual == rightActual
        case (.invalidSnapshotTokenData(let leftError),
              .invalidSnapshotTokenData(let rightError)):
            return OpalBase.Network.checkFailureEquivalence(leftError, rightError)
        case (.invalidSnapshotDuplicateTokenDelta(let leftTokenData),
              .invalidSnapshotDuplicateTokenDelta(let rightTokenData)):
            return leftTokenData == rightTokenData
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
