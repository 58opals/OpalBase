// KeySigningKeyValidator.swift

import Foundation
import OpalCrypto
import Testing
@testable import OpalBase

@Suite("OpalBase.Key.SigningKey", .tags(.unit))
struct KeySigningKeyValidator {
    @Test(
        "redacts text representations",
        arguments: SigningKeyTextRepresentationCase.allCases
    )
    func redactsTextRepresentations(_ representationCase: SigningKeyTextRepresentationCase) throws {
        let privateKey = Data(repeating: 0x02, count: 32)
        let signingKey = try OpalBase.Key.SigningKey(rawRepresentation: privateKey)
        let representation = representationCase.makeString(for: signingKey)

        #expect(representation.contains("redacted"))
        #expect(representation.contains(privateKey.hexadecimalString) == false)
    }

    @Test("redacts reflection")
    func redactsReflection() throws {
        let privateKey = Data(repeating: 0x02, count: 32)
        let signingKey = try OpalBase.Key.SigningKey(rawRepresentation: privateKey)
        let mirror = Mirror(reflecting: signingKey)
        let reflectedLabels = mirror.children.compactMap(\.label)
        let reflectedValues = mirror.children.map { String(describing: $0.value) }

        #expect(reflectedLabels.contains("privateKey"))
        #expect(reflectedValues.contains("redacted"))
        #expect(reflectedLabels.contains("opalCryptoSigningKey") == false)
        #expect(reflectedLabels.contains("publicKeyValue") == false)
        #expect(reflectedValues.contains { $0.contains(privateKey.hexadecimalString) } == false)
    }

    @Test("derives matching compressed public key")
    func derivesMatchingCompressedPublicKey() throws {
        let privateKey = Data(repeating: 0x02, count: 32)
        let signingKey = try OpalBase.Key.SigningKey(rawRepresentation: privateKey)
        let legacyPrivateKey = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKey)
        let expectedPublicKey = try OpalCrypto.Secp256k1.derivePublicKey(from: legacyPrivateKey)

        #expect(signingKey.publicKey.compressedData == expectedPublicKey.rawRepresentation)
    }

    @Test(
        "matches legacy raw-key signing",
        arguments: SigningAlgorithmParityCase.allCases
    )
    func matchesLegacyRawKeySigning(_ parityCase: SigningAlgorithmParityCase) throws {
        let privateKey = Data(repeating: 0x02, count: 32)
        let signingKey = try OpalBase.Key.SigningKey(rawRepresentation: privateKey)
        let legacyPrivateKey = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKey)
        let digest = try OpalCrypto.Signature.Digest(
            rawRepresentation: Data(repeating: 0x33, count: 32)
        )

        let signatures = try parityCase.makeSignatures(
            signingKey: signingKey,
            legacyPrivateKey: legacyPrivateKey,
            digest: digest
        )

        #expect(signatures.scoped == signatures.legacy)
    }

    enum SigningAlgorithmParityCase: CaseIterable, CustomStringConvertible, Sendable {
        case ecdsaDER
        case schnorr

        var description: String {
            switch self {
            case .ecdsaDER:
                "ECDSA DER"
            case .schnorr:
                "Schnorr"
            }
        }

        func makeSignatures(
            signingKey: OpalBase.Key.SigningKey,
            legacyPrivateKey: OpalCrypto.Secp256k1.PrivateKey,
            digest: OpalCrypto.Signature.Digest
        ) throws -> (scoped: Data, legacy: Data) {
            switch self {
            case .ecdsaDER:
                let scoped = try signingKey.signECDSA(digest: digest, format: .der)
                let legacy = try OpalCrypto.Signature.ECDSA.sign(
                    digest: digest,
                    privateKey: legacyPrivateKey,
                    format: .der
                )
                #expect(scoped.format == legacy.format)
                return (scoped.rawRepresentation, legacy.rawRepresentation)
            case .schnorr:
                let scoped = try signingKey.signSchnorr(digest: digest)
                let legacy = try OpalCrypto.Signature.Schnorr.sign(
                    digest: digest,
                    privateKey: legacyPrivateKey
                )
                return (scoped.rawRepresentation, legacy.rawRepresentation)
            }
        }
    }

    enum SigningKeyTextRepresentationCase: CaseIterable, CustomStringConvertible, Sendable {
        case describing
        case reflecting

        var description: String {
            switch self {
            case .describing:
                "String(describing:)"
            case .reflecting:
                "String(reflecting:)"
            }
        }

        func makeString(for signingKey: OpalBase.Key.SigningKey) -> String {
            switch self {
            case .describing:
                String(describing: signingKey)
            case .reflecting:
                String(reflecting: signingKey)
            }
        }
    }
}
