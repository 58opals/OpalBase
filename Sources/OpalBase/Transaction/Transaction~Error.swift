import Foundation

extension Transaction {
    enum Error: Swift.Error {
        case insufficientFunds(required: UInt64)
        case accountNotFound
        case cannotCreateTransaction
        case cannotBroadcastTransaction
        case unsupportedHashType
        case outputValueIsLessThanTheDustLimit
    }
}
