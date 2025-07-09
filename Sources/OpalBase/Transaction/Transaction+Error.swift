// Transaction+Error.swift

import Foundation

extension Transaction {
    public enum Error: Swift.Error {
        case insufficientFunds(required: UInt64)
        case accountNotFound
        case cannotCreateTransaction
        case cannotBroadcastTransaction
        case unsupportedHashType
        case unsupportedSignatureFormat
        case outputValueIsLessThanTheDustLimit
    }
}
