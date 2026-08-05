// OpalBase+ReusablePaymentAddress+KeyOrigin.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    /// Stable, non-secret identifiers for the authorities that can reauthorize
    /// Cash Code scanning and spending after restoration.
    public struct KeyOrigin: Codable, Hashable, Sendable {
        public let scanKeyIdentifier: String
        public let spendKeyIdentifier: String

        public init(
            scanKeyIdentifier: String,
            spendKeyIdentifier: String
        ) throws {
            guard Self.isValid(scanKeyIdentifier),
                  Self.isValid(spendKeyIdentifier)
            else {
                throw Error.invalidKeyOrigin
            }
            self.scanKeyIdentifier = scanKeyIdentifier
            self.spendKeyIdentifier = spendKeyIdentifier
        }

        static func isValid(_ identifier: String) -> Bool {
            !identifier.isEmpty && identifier.utf8.count <= 1_024
        }
    }
}
