// Satoshi+Error.swift

import Foundation

extension Satoshi {
    enum Error: Swift.Error {
        case exceedsMaximumAmount
        case negativeResult
    }
}
