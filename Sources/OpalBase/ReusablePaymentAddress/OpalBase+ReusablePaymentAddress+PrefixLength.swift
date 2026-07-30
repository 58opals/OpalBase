// OpalBase+ReusablePaymentAddress+PrefixLength.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public enum PrefixLength: UInt8, Sendable, Hashable, Codable {
        case fourBits = 4
        case eightBits = 8
        case twelveBits = 12
        case sixteenBits = 16

        public var bitCount: Int {
            Int(rawValue)
        }
    }
}
