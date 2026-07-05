// OpalBase+ReusablePaymentAddress+Error.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public enum Error: Swift.Error, Sendable, Equatable {
        case specificationUnavailable
        case invalidPrefixLength(Int)
        case invalidHashPrefix
        case invalidBlockHeight(Int)
        case invalidLabel(String)
    }
}
