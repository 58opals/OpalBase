import Foundation

extension Transaction {
    enum Error: Swift.Error {
        case insufficientFunds
        case accountNotFound
        case cannotCreateTransaction
    }
}
