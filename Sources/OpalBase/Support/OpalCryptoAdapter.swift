// OpalCryptoAdapter.swift

import Foundation
import OpalCrypto

enum OpalCryptoAdapter {
    enum Error: Swift.Error, Equatable {
        case invalidSerializedExtendedKey
        case invalidSerializedAccountExtendedPublicKey
        case accountExtendedPublicKeyDoesNotMatchAccount
    }

    static let cashAddrCharacters: Set<Character> = Set("qpzry9x8gf2tvdw0s3jn54khce6mua7l")

    static func sha256(_ data: Data) -> Data {
        OpalCrypto.Hashing.sha256(data)
    }

    static func hash160(_ data: Data) -> Data {
        OpalCrypto.Hashing.hash160(data)
    }

    static func hash256(_ data: Data) -> Data {
        OpalCrypto.Hashing.hash256(data)
    }

    static func encodeBase58(_ data: Data) -> String {
        OpalCrypto.Encoding.encodeBase58(data)
    }

    static func decodeBase58(_ text: String) -> Data? {
        OpalCrypto.Encoding.decodeBase58(text)
    }

    static func encodeBase32(_ data: Data, interpretedAsFiveBitValues: Bool) throws -> String {
        if interpretedAsFiveBitValues {
            return try OpalCrypto.Encoding.encodeBase32Values(
                OpalCrypto.Encoding.FiveBitValues(rawRepresentation: data)
            )
        }
        return try OpalCrypto.Encoding.encodeBase32Bytes(data)
    }

    static func decodeBase32(_ text: String, interpretedAsFiveBitValues: Bool) throws -> Data {
        if interpretedAsFiveBitValues {
            return try OpalCrypto.Encoding.decodeBase32Values(text).rawRepresentation
        }
        return try OpalCrypto.Encoding.decodeBase32Bytes(text)
    }

    static func computePolymod(_ values: [UInt8]) throws -> UInt64 {
        let fiveBitValues = try OpalCrypto.Encoding.FiveBitValues(rawRepresentation: Data(values))
        return OpalCrypto.Encoding.computePolymodChecksum(fiveBitValues)
    }

    static func deriveCompressedPublicKey(from privateKeyData: Data) throws -> Data {
        let privateKey = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKeyData)
        return try OpalCrypto.Secp256k1.derivePublicKey(from: privateKey).rawRepresentation
    }

    static func validateCompressedPublicKey(_ compressedPublicKeyData: Data) throws -> Data {
        try OpalCrypto.Secp256k1.PublicKey(
            rawRepresentation: compressedPublicKeyData
        ).compressedRepresentation
    }

    static func walletImportFormat(privateKeyData: Data, isCompressed: Bool = true) throws -> String {
        let privateKey = try OpalCrypto.Secp256k1.PrivateKey(rawRepresentation: privateKeyData)
        return try OpalCrypto.Key.WIF(privateKey: privateKey, isCompressed: isCompressed).serialize()
    }

    static func parseWalletImportFormat(_ text: String) throws -> OpalCrypto.Key.WIF {
        try OpalCrypto.Key.WIF(text)
    }

    static func fingerprint(of compressedPublicKeyData: Data) -> Data {
        Data(hash160(compressedPublicKeyData).prefix(4))
    }

    static func makeSerializedAccountExtendedPublicKey(
        seed: Data,
        purpose: OpalBase.Key.DerivationPath.Purpose,
        coinType: OpalBase.Key.DerivationPath.CoinType,
        account: OpalBase.Key.DerivationPath.Account
    ) throws -> String {
        let rootExtendedPrivateKey = try OpalCrypto.Key.ExtendedPrivate.root(
            seed: OpalCrypto.Key.Seed(rawRepresentation: seed)
        )
        return try makeAccountExtendedPublicKey(
            rootExtendedPrivateKey: rootExtendedPrivateKey,
            purpose: purpose,
            coinType: coinType,
            account: account
        ).serialize()
    }

    static func makeAccountExtendedPublicKey(
        rootExtendedPrivateKey: OpalCrypto.Key.ExtendedPrivate,
        purpose: OpalBase.Key.DerivationPath.Purpose,
        coinType: OpalBase.Key.DerivationPath.CoinType,
        account: OpalBase.Key.DerivationPath.Account
    ) throws -> OpalCrypto.Key.ExtendedPublic {
        try rootExtendedPrivateKey.derived(indices: [
            purpose.hardenedIndex,
            coinType.hardenedIndex,
            account.deriveHardenedIndex()
        ]).publicKey
    }

    static func parseAccountExtendedPublicKey(
        _ serialized: String,
        account: OpalBase.Key.DerivationPath.Account
    ) throws -> OpalCrypto.Key.ExtendedPublic {
        let accountExtendedPublicKey: OpalCrypto.Key.ExtendedPublic
        do {
            accountExtendedPublicKey = try OpalCrypto.Key.ExtendedPublic(serialized)
        } catch {
            throw Error.invalidSerializedAccountExtendedPublicKey
        }

        guard accountExtendedPublicKey.depth == 3 else {
            throw Error.invalidSerializedAccountExtendedPublicKey
        }

        guard accountExtendedPublicKey.childIndex == (try account.deriveHardenedIndex()) else {
            throw Error.accountExtendedPublicKeyDoesNotMatchAccount
        }

        return accountExtendedPublicKey
    }

    static func serializedExtendedKeyData(_ serialized: String) throws -> Data {
        guard let data = decodeBase58(serialized) else {
            throw Error.invalidSerializedExtendedKey
        }
        return data
    }
}
