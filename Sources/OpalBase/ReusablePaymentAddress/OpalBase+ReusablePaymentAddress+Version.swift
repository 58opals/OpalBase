// OpalBase+ReusablePaymentAddress+Version.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct Version: Sendable, Hashable, Codable {
        public let rawValue: UInt8

        public init(rawValue: UInt8) {
            self.rawValue = rawValue
        }
    }
}
