// OpalBase+ReusablePaymentAddress+InputHashPrefix.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct InputHashPrefix: Sendable, Hashable {
        public let hash: Data
        public let prefixLength: PrefixLength

        public init(hash: Data, prefixLength: PrefixLength) throws {
            guard !hash.isEmpty, prefixLength.bitCount <= hash.count * 8 else {
                throw OpalBase.ReusablePaymentAddress.Error.invalidHashPrefix
            }
            self.hash = Data(hash)
            self.prefixLength = prefixLength
        }
    }
}
