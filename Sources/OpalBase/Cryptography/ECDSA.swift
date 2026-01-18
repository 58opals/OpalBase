// ECDSA.swift

import Foundation
import BigInt
import SwiftSchnorr
import P256K

public struct ECDSA {
    static let numberOfPointsOnTheCurveWeCanHit = BigUInt("115792089237316195423570985008687907852837564279074904382605163141518161494337")
    
    static func add(to compressedPublicKey: Data, tweak: Data) throws -> Data {
        let secp256k1PublicKey = try ECDSA.derivePublicKey(from: compressedPublicKey, in: .compressed)
        let pointAdded = try secp256k1PublicKey.add(Array<UInt8>(tweak), format: .compressed)
        return pointAdded.dataRepresentation
    }
}

extension ECDSA {
    enum Error: Swift.Error {
        case invalidCompressedPublicKeyLength
        case invalidCompressedPublicKeyPrefix
        case invalidDigestLength(expected: Int, actual: Int)
        case invalidHashIterationCount
        case schnorrBCHNotImplementedYet
    }
}

extension ECDSA {
    static func derivePublicKey(from privateKey: Data) throws -> P256K.Signing.PublicKey {
        let secp256k1PrivateKey = try P256K.Signing.PrivateKey(dataRepresentation: privateKey)
        return secp256k1PrivateKey.publicKey
    }
    
    static func derivePublicKey(from publicKey: Data, in format: P256K.Format = .compressed) throws -> P256K.Signing.PublicKey {
        let secp256k1PublicKey = try P256K.Signing.PublicKey(dataRepresentation: publicKey, format: format)
        return secp256k1PublicKey
    }
}

extension ECDSA {
    public enum SignatureFormat {
        /// Signature wire-format used by signing and verification.
        /// - Note:
        ///   - **OP_CHECKSIG + ECDSA requires DER**. Using `.raw` or `.compact` with CHECKSIG is invalid at consensus.
        ///   - Schnorr is allowed for CHECKSIG as per BCH consensus.
        case ecdsa(ECDSA)
        case schnorr // Bitcoin Cash Schnorr (May 2019+).
        case schnorrBIP340 // BIP340/x-only Schnorr. Not valid for BCH consensus signing.
        
        public enum ECDSA {
            case raw
            case compact
            case der
        }
    }
}

extension ECDSA {
    static func sign(message: Data, with privateKey: PrivateKey, in format: SignatureFormat) throws -> Data {
        switch format {
        case .ecdsa(let ecdsa):
            let ecdsaPrivateKey = try P256K.Signing.PrivateKey(dataRepresentation: privateKey.rawData)
            let ecdsaSignature = try ecdsaPrivateKey.signature(for: message)
            switch ecdsa {
            case .raw:
                return ecdsaSignature.dataRepresentation
            case .compact:
                return try ecdsaSignature.compactRepresentation
            case .der:
                return try ecdsaSignature.derRepresentation
            }
        case .schnorr:
            guard message.count == 32 else {
                throw Error.invalidDigestLength(expected: 32, actual: message.count)
            }
            let signature = try BCHSchnorr.sign(digest32: message, privateKey32: privateKey.rawData)
            return signature.raw64
        case .schnorrBIP340:
            let schnorrPrivateKey = try P256K.Schnorr.PrivateKey(dataRepresentation: privateKey.rawData)
            let schnorrSignature = try schnorrPrivateKey.signature(for: message)
            return schnorrSignature.dataRepresentation
        }
    }
    
    static func sign(message: ECDSA.Message, with privateKey: PrivateKey, in format: SignatureFormat) throws -> Data {
        switch format {
        case .ecdsa, .schnorrBIP340:
            let signerInput = try message.makeDataForSignerHashingOnceSHA256Internally()
            return try sign(message: signerInput, with: privateKey, in: format)
        case .schnorr:
            throw Error.schnorrBCHNotImplementedYet
        }
    }
}

extension ECDSA {
    static func verify(signature: Data, message: Data, publicKey: PublicKey, format: SignatureFormat) throws -> Bool {
        let compressedPublicKey = publicKey.compressedData
        guard compressedPublicKey.count == 33 else { throw Error.invalidCompressedPublicKeyLength }
        let prefix = compressedPublicKey[0]
        guard prefix == 0x02 || prefix == 0x03 else { throw Error.invalidCompressedPublicKeyPrefix }
        
        switch format {
        case .ecdsa(let ecdsa):
            let ecdsaPublicKey = try P256K.Signing.PublicKey(dataRepresentation: compressedPublicKey, format: .compressed)
            switch ecdsa {
            case .raw:
                let ecdsaSignature = try P256K.Signing.ECDSASignature(dataRepresentation: signature)
                return ecdsaPublicKey.isValidSignature(ecdsaSignature, for: message)
            case .compact:
                let ecdsaSignature = try P256K.Signing.ECDSASignature(compactRepresentation: signature)
                return ecdsaPublicKey.isValidSignature(ecdsaSignature, for: message)
            case .der:
                let ecdsaSignature = try P256K.Signing.ECDSASignature(derRepresentation: signature)
                return ecdsaPublicKey.isValidSignature(ecdsaSignature, for: message)
            }
        case .schnorr:
            do {
                guard message.count == 32 else {
                    throw Error.invalidDigestLength(expected: 32, actual: message.count)
                }
                let schnorrSignature = try BCHSchnorr.Signature(raw64: signature)
                return try BCHSchnorr.verify(
                    signature: schnorrSignature,
                    digest32: message,
                    publicKey: publicKey.compressedData
                )
            } catch {
                return false
            }
        case .schnorrBIP340:
            let xCoordinate = compressedPublicKey[1..<33]
            let schnorrPublicKey = P256K.Schnorr.XonlyKey(dataRepresentation: xCoordinate)
            let schnorrSignature = try P256K.Schnorr.SchnorrSignature(dataRepresentation: signature)
            return schnorrPublicKey.isValidSignature(schnorrSignature, for: message)
        }
    }
    
    static func verify(signature: Data, message: ECDSA.Message, publicKey: PublicKey, format: SignatureFormat) throws -> Bool {
        switch format {
        case .ecdsa, .schnorrBIP340:
            let signerInput = try message.makeDataForSignerHashingOnceSHA256Internally()
            return try verify(signature: signature, message: signerInput, publicKey: publicKey, format: format)
        case .schnorr:
            throw Error.schnorrBCHNotImplementedYet
        }
    }
}
