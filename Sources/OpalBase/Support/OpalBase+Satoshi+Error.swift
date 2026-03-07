// OpalBase+Satoshi+Error.swift

import Foundation

extension _OpalBase.Satoshi {
    enum Error: Swift.Error {
        case exceedsMaximumAmount
        case negativeResult
        case invalidPrecision
        case divisionByZero
    }
}
