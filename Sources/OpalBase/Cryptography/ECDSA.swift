// ECDSA.swift

import Foundation

public struct ECDSA {
    static func add(to compressedPublicKey: Data, tweak: Data) throws -> Data {
        try Secp256k1.Operation.tweakAddPublicKey(compressedPublicKey,
                                                  tweak32: tweak,
                                                  format: .compressed)
    }
}

extension ECDSA {
    enum Error: Swift.Error {
        case invalidCompressedPublicKeyLength
        case invalidCompressedPublicKeyPrefix
        case invalidDigestLength(expected: Int, actual: Int)
        case invalidHashIterationCount
    }
}

extension ECDSA {
    static func derivePublicKey(from privateKey: Data) throws -> Data {
        try Secp256k1.Operation.derivePublicKey(fromPrivateKey32: privateKey, format: .compressed)
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
        
        public enum ECDSA {
            case raw
            case compact
            case der
        }
    }
}

extension ECDSA {
    static func sign(message: Data,
                     with privateKey: PrivateKey,
                     in format: SignatureFormat,
                     nonceFunction: NonceFunction = .rfc6979BchDefault) throws -> Data {
        switch format {
        case .ecdsa(let ecdsa):
            let digest32 = SHA256.hash(message)
            let ecdsaSignature = try Secp256k1.sign(digest32: digest32,
                                                    privateKey32: privateKey.rawData,
                                                    nonce: makeEcdsaNonce(from: nonceFunction))
            switch ecdsa {
            case .raw:
                return ecdsaSignature.raw64
            case .compact:
                return ecdsaSignature.raw64
            case .der:
                return try ecdsaSignature.encodeDER()
            }
        case .schnorr:
            guard message.count == 32 else { throw Error.invalidDigestLength(expected: 32, actual: message.count) }
            let signature = try Schnorr.sign(digest32: message,
                                             privateKey32: privateKey.rawData,
                                             nonce: nonceFunction)
            return signature.raw64
        }
    }
    
    static func sign(message: ECDSA.Message,
                     with privateKey: PrivateKey,
                     in format: SignatureFormat,
                     nonceFunction: NonceFunction = .rfc6979BchDefault) throws -> Data {
        switch format {
        case .ecdsa:
            let signerInput = try message.makeDataForSignerHashingOnceSHA256Internally()
            return try sign(message: signerInput, with: privateKey, in: format, nonceFunction: nonceFunction)
        case .schnorr:
            let digest32 = try message.makeConsensusDigest32()
            return try sign(message: digest32, with: privateKey, in: .schnorr, nonceFunction: nonceFunction)
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
            let digest32 = SHA256.hash(message)
            switch ecdsa {
            case .raw:
                let ecdsaSignature = try Secp256k1.Signature(raw64: signature)
                return try Secp256k1.verify(signature: ecdsaSignature, digest32: digest32, publicKey: compressedPublicKey)
            case .compact:
                let ecdsaSignature = try Secp256k1.Signature(raw64: signature)
                return try Secp256k1.verify(signature: ecdsaSignature, digest32: digest32, publicKey: compressedPublicKey)
            case .der:
                return try Secp256k1.verify(derEncodedSignature: signature,
                                            digest32: digest32,
                                            publicKey: compressedPublicKey)
            }
        case .schnorr:
            do {
                guard message.count == 32 else { throw Error.invalidDigestLength(expected: 32, actual: message.count) }
                let schnorrSignature = try Schnorr.Signature(raw64: signature)
                return try Schnorr.verify(signature: schnorrSignature,
                                          digest32: message,
                                          publicKey: publicKey.compressedData)
            } catch {
                return false
            }
        }
    }
    
    static func verify(signature: Data, message: ECDSA.Message, publicKey: PublicKey, format: SignatureFormat) throws -> Bool {
        switch format {
        case .ecdsa:
            let signerInput = try message.makeDataForSignerHashingOnceSHA256Internally()
            return try verify(signature: signature, message: signerInput, publicKey: publicKey, format: format)
        case .schnorr:
            let digest32 = try message.makeConsensusDigest32()
            return try verify(signature: signature, message: digest32, publicKey: publicKey, format: .schnorr)
        }
    }
}

extension ECDSA {
    static func detectFormat(signatureCore: Data) -> SignatureFormat? {
        if signatureCore.count == 64 { return .schnorr }
        do {
            _ = try Secp256k1.Signature(derEncoded: signatureCore)
            return .ecdsa(.der)
        } catch {
            return nil
        }
    }
}

private extension ECDSA {
    static func makeEcdsaNonce(from nonceFunction: NonceFunction) -> NonceFunction.ECDSA {
        switch nonceFunction {
        case .systemRandom:
            return .systemRandom
        case .rfc6979BchDefault, .bipSchnorrDeterministic:
            return .rfc6979Sha256
        }
    }
}
