// SecureEnclaveAdapter~Cryptography.swift

import CryptoKit
import Foundation
import Security

extension SecureEnclaveAdapter {
    static func encrypt(
        _ plaintext: Data,
        applicationTag: Data
    ) throws -> _OpalBase.Storage.Security.Ciphertext {
        let privateKey = try loadOrCreatePrivateKey(applicationTag: applicationTag)
        let ephemeralPrivateKey = P256.KeyAgreement.PrivateKey()
        let sharedSecret = try ephemeralPrivateKey.sharedSecretFromKeyAgreement(with: privateKey.publicKey)
        let salt = try randomBytes(count: 32)
        let symmetricKey = deriveSymmetricKey(
            sharedSecret: sharedSecret,
            salt: salt,
            applicationTag: applicationTag
        )
        let sealedBox = try AES.GCM.seal(plaintext, using: symmetricKey)

        guard let combinedCiphertext = sealedBox.combined else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.Code.coderInvalidValue.rawValue,
                userInfo: [NSDebugDescriptionErrorKey: "AES-GCM output did not produce a combined ciphertext representation."]
            )
        }

        let envelope = SecureEnclaveEnvelope(
            version: envelopeVersion,
            salt: salt,
            ephemeralPublicKeyRepresentation: ephemeralPrivateKey.publicKey.x963Representation,
            combinedCiphertext: combinedCiphertext
        )
        let payload = try JSONEncoder().encode(envelope)

        return .init(mode: .secureEnclave, payload: payload)
    }

    static func decrypt(
        _ ciphertext: _OpalBase.Storage.Security.Ciphertext,
        applicationTag: Data
    ) throws -> Data {
        let envelope = try JSONDecoder().decode(SecureEnclaveEnvelope.self, from: ciphertext.payload)

        guard envelope.version == envelopeVersion else {
            throw NSError(
                domain: NSCocoaErrorDomain,
                code: CocoaError.Code.coderInvalidValue.rawValue,
                userInfo: [NSDebugDescriptionErrorKey: "Unsupported Secure Enclave envelope version: \(envelope.version)."]
            )
        }

        let privateKey = try loadPrivateKey(applicationTag: applicationTag)
        let ephemeralPublicKey = try P256.KeyAgreement.PublicKey(
            x963Representation: envelope.ephemeralPublicKeyRepresentation
        )
        let sharedSecret = try privateKey.sharedSecretFromKeyAgreement(with: ephemeralPublicKey)
        let symmetricKey = deriveSymmetricKey(
            sharedSecret: sharedSecret,
            salt: envelope.salt,
            applicationTag: applicationTag
        )
        let sealedBox = try AES.GCM.SealedBox(combined: envelope.combinedCiphertext)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    static func deriveSymmetricKey(
        sharedSecret: SharedSecret,
        salt: Data,
        applicationTag: Data
    ) -> SymmetricKey {
        sharedSecret.hkdfDerivedSymmetricKey(
            using: SHA256.self,
            salt: salt,
            sharedInfo: makeSharedInfo(applicationTag: applicationTag),
            outputByteCount: 32
        )
    }

    static func makeSharedInfo(applicationTag: Data) -> Data {
        var data = envelopeContext
        data.append(applicationTag)
        return data
    }

    static func randomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return errSecParam }
            return SecRandomCopyBytes(kSecRandomDefault, count, baseAddress)
        }

        guard status == errSecSuccess else {
            throw makeSecurityError(status: status, message: "Failed to generate random bytes.")
        }

        return data
    }
}
