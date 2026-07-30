// OpalBase+ReusablePaymentAddress.swift

import Foundation

extension OpalBase {
    public struct ReusablePaymentAddress: Sendable, Hashable {
        public let profile: Profile
        public let network: OpalBase.Network.Environment
        public let prefixLength: PrefixLength
        public let expiration: Expiration
        public let scanPublicKey: OpalBase.Key.PublicKey
        public let spendPublicKey: OpalBase.Key.PublicKey

        public init(
            cashCodeV1For network: OpalBase.Network.Environment,
            scanPublicKey: OpalBase.Key.PublicKey,
            spendPublicKey: OpalBase.Key.PublicKey
        ) {
            self.profile = .cashCodeV1
            self.network = network
            self.prefixLength = .sixteenBits
            self.expiration = .never
            self.scanPublicKey = scanPublicKey
            self.spendPublicKey = spendPublicKey
        }

        init(
            legacyElectronCashFor network: OpalBase.Network.Environment,
            prefixLength: PrefixLength,
            expiration: Expiration,
            scanPublicKey: OpalBase.Key.PublicKey,
            spendPublicKey: OpalBase.Key.PublicKey
        ) {
            self.profile = .legacyElectronCash
            self.network = network
            self.prefixLength = prefixLength
            self.expiration = expiration
            self.scanPublicKey = scanPublicKey
            self.spendPublicKey = spendPublicKey
        }
    }
}
