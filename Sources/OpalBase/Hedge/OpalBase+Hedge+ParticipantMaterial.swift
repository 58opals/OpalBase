// OpalBase+Hedge+ParticipantMaterial.swift

extension _OpalBase.Hedge {
    public struct ParticipantMaterial: Sendable, Equatable {
        public let side: Side
        public let payoutAddress: OpalBase.Address
        public let lockingScriptHex: String
        public let mutualRedeemPublicKeyHex: String
        public let derivedAddress: OpalBase.Account.DerivedAddress?

        public init(
            side: Side,
            payoutAddress: OpalBase.Address,
            lockingScriptHex: String,
            mutualRedeemPublicKeyHex: String,
            derivedAddress: OpalBase.Account.DerivedAddress? = nil
        ) {
            self.side = side
            self.payoutAddress = payoutAddress
            self.lockingScriptHex = lockingScriptHex.lowercased()
            self.mutualRedeemPublicKeyHex = mutualRedeemPublicKeyHex.lowercased()
            self.derivedAddress = derivedAddress
        }
    }
}
