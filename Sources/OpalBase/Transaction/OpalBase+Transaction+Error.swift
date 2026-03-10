// OpalBase+Transaction+Error.swift

import Foundation

extension _OpalBase.Transaction {
    public enum Error: Swift.Error, Equatable {
        case insufficientFunds(required: UInt64)
        case accountNotFound
        case cannotCreateTransaction
        case cannotBroadcastTransaction
        case unsupportedHashType
        case unsupportedSignatureFormat
        case outputValueIsLessThanTheDustLimit
        case sighashSingleIndexOutOfRange
        case missingUnspentTransactionOutputs
        case unspentTransactionOutputsCountMismatch(expected: Int, actual: Int)
        case transactionNotFound
        case feeCalculationOverflow(size: Int, feePerByte: UInt64)
    }
}
