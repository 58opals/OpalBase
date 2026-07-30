// OpalBase+ReusablePaymentAddress+Expiration.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public enum Expiration: Sendable, Hashable {
        case never
        case unixTime(UInt32)
    }
}
