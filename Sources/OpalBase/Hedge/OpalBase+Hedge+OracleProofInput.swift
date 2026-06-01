// OpalBase+Hedge+OracleProofInput.swift

extension _OpalBase.Hedge {
    public struct OracleProofInput: Sendable, Equatable {
        public let messageHex: String
        public let signatureHex: String
        public let publicKeyHex: String

        public init(
            messageHex: String,
            signatureHex: String,
            publicKeyHex: String
        ) {
            self.messageHex = messageHex
            self.signatureHex = signatureHex
            self.publicKeyHex = publicKeyHex
        }
    }
}
