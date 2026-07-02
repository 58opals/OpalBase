// OpalBase+Key+SigningKey.swift

import Foundation
import OpalCrypto

extension _OpalBase.Key {
    /// Opaque secp256k1 signing capability for OpalBase signing paths.
    public struct SigningKey: Sendable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
        private static let curveName = "secp256k1"
        private static let redactedMarker = "redacted"

        let opalCryptoSigningKey: OpalCrypto.Secp256k1.SigningKey
        private let publicKeyValue: OpalBase.Key.PublicKey

        /// Imports secret-bearing raw secp256k1 private-key bytes into a scoped signing capability.
        public init(rawRepresentation: Data) throws {
            let opalCryptoSigningKey = try OpalCrypto.Secp256k1.SigningKey(
                rawRepresentation: rawRepresentation
            )
            try self.init(opalCryptoSigningKey: opalCryptoSigningKey)
        }

        /// Public key derived from this signing capability.
        public var publicKey: OpalBase.Key.PublicKey {
            publicKeyValue
        }

        /// A redacted description that never includes private-key bytes.
        public var description: String {
            "OpalBase.Key.SigningKey(\(Self.redactedMarker), curve: \(Self.curveName))"
        }

        /// A redacted debug description that never includes private-key bytes.
        public var debugDescription: String {
            description
        }

        /// A redacted mirror that avoids exposing internal signing-key storage through reflection.
        public var customMirror: Mirror {
            Mirror(
                self,
                children: [
                    "curve": Self.curveName,
                    "privateKey": Self.redactedMarker,
                ],
                displayStyle: .struct
            )
        }

        init(opalCryptoSigningKey: OpalCrypto.Secp256k1.SigningKey) throws {
            self.opalCryptoSigningKey = opalCryptoSigningKey
            self.publicKeyValue = try OpalBase.Key.PublicKey(
                compressedData: opalCryptoSigningKey.publicKey.rawRepresentation
            )
        }
    }
}

extension _OpalBase.Key.SigningKey {
    func signECDSA(
        message: Data,
        format: OpalCrypto.Signature.ECDSAFormat
    ) throws -> OpalCrypto.Signature.ECDSA {
        try opalCryptoSigningKey.signECDSA(
            message: message,
            format: format
        )
    }

    func signECDSA(
        digest: OpalCrypto.Signature.Digest,
        format: OpalCrypto.Signature.ECDSAFormat
    ) throws -> OpalCrypto.Signature.ECDSA {
        try opalCryptoSigningKey.signECDSA(
            digest: digest,
            format: format
        )
    }

    func signSchnorr(
        digest: OpalCrypto.Signature.Digest
    ) throws -> OpalCrypto.Signature.Schnorr {
        try opalCryptoSigningKey.signSchnorr(digest: digest)
    }
}
