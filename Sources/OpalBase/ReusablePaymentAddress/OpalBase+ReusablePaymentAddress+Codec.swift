// OpalBase+ReusablePaymentAddress+Codec.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct Codec: Sendable {
        private let performParse: @Sendable (String) throws -> OpalBase.ReusablePaymentAddress
        private let performEncode: @Sendable (OpalBase.ReusablePaymentAddress) throws -> String

        public init(
            parse: @escaping @Sendable (String) throws -> OpalBase.ReusablePaymentAddress,
            encode: @escaping @Sendable (OpalBase.ReusablePaymentAddress) throws -> String
        ) {
            self.performParse = parse
            self.performEncode = encode
        }

        public init() {
            self.init(
                parse: { _ in throw OpalBase.ReusablePaymentAddress.Error.specificationUnavailable },
                encode: { _ in throw OpalBase.ReusablePaymentAddress.Error.specificationUnavailable }
            )
        }

        public func parse(_ paycode: String) throws -> OpalBase.ReusablePaymentAddress {
            try performParse(paycode)
        }

        public func encode(_ reusablePaymentAddress: OpalBase.ReusablePaymentAddress) throws -> String {
            try performEncode(reusablePaymentAddress)
        }
    }
}
