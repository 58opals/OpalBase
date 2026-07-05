// OpalBase+ReusablePaymentAddress.swift

import Foundation

extension OpalBase {
    public struct ReusablePaymentAddress: Sendable, Hashable {
        public let version: Version
        public let network: OpalBase.Network.Environment
        public let prefixLength: PrefixLength
        public let expiration: Expiration
        public let scanPublicKey: OpalBase.Key.PublicKey
        public let spendPublicKey: OpalBase.Key.PublicKey

        public init(
            version: Version,
            network: OpalBase.Network.Environment,
            prefixLength: PrefixLength,
            expiration: Expiration,
            scanPublicKey: OpalBase.Key.PublicKey,
            spendPublicKey: OpalBase.Key.PublicKey
        ) {
            self.version = version
            self.network = network
            self.prefixLength = prefixLength
            self.expiration = expiration
            self.scanPublicKey = scanPublicKey
            self.spendPublicKey = spendPublicKey
        }
    }
}
