// OpalBase+ReusablePaymentAddress+ReceivingCapability.swift

extension _OpalBase.ReusablePaymentAddress {
    /// Opaque authority for one rederived Cash Code receiving key.
    public struct ReceivingCapability: Sendable, CustomStringConvertible,
        CustomDebugStringConvertible, CustomReflectable
    {
        public let outpoint: OpalBase.Transaction.Outpoint
        public let publicKey: OpalBase.Key.PublicKey

        let signingKey: OpalBase.Key.SigningKey

        public var description: String {
            "OpalBase.ReusablePaymentAddress.ReceivingCapability(redacted)"
        }

        public var debugDescription: String {
            description
        }

        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "authority": "redacted",
                    "publicKey": publicKey,
                    "outpoint": outpoint,
                ],
                displayStyle: .struct
            )
        }

        init(
            outpoint: OpalBase.Transaction.Outpoint,
            signingKey: OpalBase.Key.SigningKey
        ) {
            self.outpoint = outpoint
            self.publicKey = signingKey.publicKey
            self.signingKey = signingKey
        }
    }
}
