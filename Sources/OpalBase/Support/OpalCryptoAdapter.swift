// OpalCryptoAdapter.swift

import Foundation
import OpalCrypto

enum OpalCryptoAdapter {
    static let cashAddressCharacters: Set<Character> = Set("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    static func sha256(_ data: Data) -> Data {
        OpalCrypto.Hashing.computeSHA256(data)
    }

    static func hash160(_ data: Data) -> Data {
        OpalCrypto.Hashing.computeHash160(data)
    }

    static func hash256(_ data: Data) -> Data {
        OpalCrypto.Hashing.computeHash256(data)
    }

    static func encodeBase58(_ data: Data) -> String {
        OpalCrypto.Encoding.encodeBase58(data)
    }

    static func decodeBase58(_ text: String) -> Data? {
        OpalCrypto.Encoding.decodeBase58(text)
    }

    static func encodeBase32(_ data: Data, interpretedAsFiveBitValues: Bool) -> String {
        OpalCrypto.Encoding.encodeBase32(data, interpretedAsFiveBitValues: interpretedAsFiveBitValues)
    }

    static func decodeBase32(_ text: String, interpretedAsFiveBitValues: Bool) throws -> Data {
        try OpalCrypto.Encoding.decodeBase32(text, interpretedAsFiveBitValues: interpretedAsFiveBitValues)
    }

    static func computePolymod(_ values: [UInt8]) -> UInt64 {
        OpalCrypto.Encoding.computePolymodChecksum(values)
    }

    static func deriveCompressedPublicKey(from privateKeyData: Data) throws -> Data {
        try OpalCrypto.Signature.derivePublicKey(fromPrivateKey: privateKeyData)
    }

    static func deriveCompressedPublicKeys(from privateKeyDataList: [Data]) async throws -> [Data] {
        try await OpalCrypto.Secp256k1.deriveCompressedPublicKeys(from: privateKeyDataList)
    }

    static func walletImportFormat(privateKeyData: Data, isCompressed: Bool = true) throws -> String {
        try OpalCrypto.Key.WIF(privateKey: privateKeyData, isCompressed: isCompressed).serialize()
    }

    static func parseWalletImportFormat(_ text: String) throws -> OpalCrypto.Key.WIF {
        try OpalCrypto.Key.WIF(text)
    }

    static func fingerprint(of compressedPublicKeyData: Data) -> Data {
        Data(hash160(compressedPublicKeyData).prefix(4))
    }

    static func serializedExtendedKeyData(_ serialized: String) -> Data {
        guard let data = decodeBase58(serialized) else {
            preconditionFailure("Serialized extended keys must remain valid base58-check strings.")
        }
        return data
    }
}
