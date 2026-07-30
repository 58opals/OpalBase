// OpalBase+ReusablePaymentAddress+FilterPrefix.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct FilterPrefix: Sendable, Hashable {
        /// Prefix length in bits.
        public let bitCount: Int

        /// Lowercase hexadecimal prefix used by an RPA-capable backend.
        ///
        /// Treat this value as wallet-identifying query material. Do not log or
        /// persist it outside the recovery state that owns the reusable payment
        /// address.
        public let hexadecimalString: String

        init(
            scanPublicKey: OpalBase.Key.PublicKey,
            prefixLength: PrefixLength
        ) {
            let xCoordinate = scanPublicKey.compressedData.dropFirst()
            self.bitCount = prefixLength.bitCount
            self.hexadecimalString = String(
                Data(xCoordinate).hexadecimalString.prefix(prefixLength.bitCount / 4)
            )
        }

        /// Returns whether the canonical serialized transaction input has this
        /// leading double-SHA-256 prefix.
        public func matches(_ input: OpalBase.Transaction.Input) -> Bool {
            OpalCryptoAdapter.hash256(input.encode())
                .hexadecimalString
                .hasPrefix(hexadecimalString)
        }
    }
}

extension _OpalBase.ReusablePaymentAddress {
    /// Backend filter prefix derived from the leading x-coordinate bits of the
    /// compressed scan public key.
    public var filterPrefix: FilterPrefix {
        FilterPrefix(
            scanPublicKey: scanPublicKey,
            prefixLength: prefixLength
        )
    }
}
