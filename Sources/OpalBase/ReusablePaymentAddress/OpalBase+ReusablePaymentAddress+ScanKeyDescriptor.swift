// OpalBase+ReusablePaymentAddress+ScanKeyDescriptor.swift

import Foundation

extension _OpalBase.ReusablePaymentAddress {
    public struct ScanKeyDescriptor: Sendable, Hashable {
        public let scanPublicKey: OpalBase.Key.PublicKey
        public let derivationPath: OpalBase.Key.DerivationPath?

        public init(
            scanPublicKey: OpalBase.Key.PublicKey,
            derivationPath: OpalBase.Key.DerivationPath? = nil
        ) {
            self.scanPublicKey = scanPublicKey
            self.derivationPath = derivationPath
        }
    }
}
