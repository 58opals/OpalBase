// SecureEnclaveAdapter+Cryptography.swift

import CryptoKit
import Foundation
import Security

extension SecureEnclaveAdapter {
    static func encrypt(
        _ plaintext: Data,
        applicationTag: Data
    ) throws -> _OpalBase.Storage.Security.Ciphertext {
        let privateKey = try loadOrCreatePrivateKey(applicationTag: applicationTag)
        let publicKey = try copyPublicKey(for: privateKey)
        let ephemeralPrivateKey = try createEphemeralPrivateKey()
        let ephemeralPublicKey = try copyPublicKey(for: ephemeralPrivateKey)
        let sharedSecret = try copyKeyAgreementSharedSecret(
            privateKey: ephemeralPrivateKey,
            publicKey: publicKey
        )
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
            ephemeralPublicKeyRepresentation: try externalRepresentation(
                of: ephemeralPublicKey,
                message: "Failed to export the ephemeral public key."
            ),
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
        let ephemeralPublicKey = try makePublicKey(
            x963Representation: envelope.ephemeralPublicKeyRepresentation
        )
        let sharedSecret = try copyKeyAgreementSharedSecret(
            privateKey: privateKey,
            publicKey: ephemeralPublicKey
        )
        let symmetricKey = deriveSymmetricKey(
            sharedSecret: sharedSecret,
            salt: envelope.salt,
            applicationTag: applicationTag
        )
        let sealedBox = try AES.GCM.SealedBox(combined: envelope.combinedCiphertext)
        return try AES.GCM.open(sealedBox, using: symmetricKey)
    }

    static func deriveSymmetricKey(
        sharedSecret: Data,
        salt: Data,
        applicationTag: Data
    ) -> SymmetricKey {
        HKDF<SHA256>.deriveKey(
            inputKeyMaterial: SymmetricKey(data: sharedSecret),
            salt: salt,
            info: makeSharedInfo(applicationTag: applicationTag),
            outputByteCount: 32
        )
    }

    static func createEphemeralPrivateKey() throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeySizeInBits as String: 256,
            kSecPrivateKeyAttrs as String: [
                kSecAttrIsPermanent as String: false,
            ],
        ]

        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            if let error {
                throw normalizeProtectionAvailabilityError(error.takeRetainedValue() as Swift.Error)
            }

            throw makeSecurityError(status: errSecAllocate, message: "Failed to create an ephemeral key agreement key.")
        }

        return privateKey
    }

    static func copyPublicKey(for privateKey: SecKey) throws -> SecKey {
        guard let publicKey = SecKeyCopyPublicKey(privateKey) else {
            throw makeSecurityError(status: errSecDecode, message: "Failed to resolve the Secure Enclave public key.")
        }

        return publicKey
    }

    static func makePublicKey(x963Representation: Data) throws -> SecKey {
        let attributes: [String: Any] = [
            kSecAttrKeyType as String: kSecAttrKeyTypeECSECPrimeRandom,
            kSecAttrKeyClass as String: kSecAttrKeyClassPublic,
            kSecAttrKeySizeInBits as String: 256,
        ]

        var error: Unmanaged<CFError>?
        guard let publicKey = SecKeyCreateWithData(
            x963Representation as CFData,
            attributes as CFDictionary,
            &error
        ) else {
            if let error {
                throw error.takeRetainedValue() as Swift.Error
            }

            throw makeSecurityError(status: errSecDecode, message: "Failed to decode the ephemeral public key.")
        }

        return publicKey
    }

    static func externalRepresentation(of publicKey: SecKey, message: String) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let representation = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
            if let error {
                throw error.takeRetainedValue() as Swift.Error
            }

            throw makeSecurityError(status: errSecDecode, message: message)
        }

        return representation
    }

    static func copyKeyAgreementSharedSecret(privateKey: SecKey, publicKey: SecKey) throws -> Data {
        var error: Unmanaged<CFError>?
        guard let sharedSecret = SecKeyCopyKeyExchangeResult(
            privateKey,
            SecKeyAlgorithm.ecdhKeyExchangeStandard,
            publicKey,
            [:] as CFDictionary,
            &error
        ) as Data? else {
            if let error {
                throw normalizeProtectionAvailabilityError(error.takeRetainedValue() as Swift.Error)
            }

            throw makeSecurityError(status: errSecDecode, message: "Secure Enclave key agreement failed.")
        }

        return sharedSecret
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
