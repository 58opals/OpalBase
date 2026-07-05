// OpalBase+ReusablePaymentAddress+PrefixLength.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct PrefixLength: Sendable, Hashable, Codable {
        public let bitCount: Int

        public init(bitCount: Int) throws {
            guard bitCount >= 0 else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidPrefixLength(bitCount)
            }
            self.bitCount = bitCount
        }
    }
}
