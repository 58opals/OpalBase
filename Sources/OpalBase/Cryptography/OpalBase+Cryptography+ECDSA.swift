// OpalBase+Cryptography+ECDSA.swift

import Foundation

extension _OpalBase.Cryptography {
    public struct ECDSA {
        static func add(to compressedPublicKey: Data, tweak: Data) throws -> Data {
            try OpalBase.Cryptography.Secp256k1.Operation.tweakAddPublicKey(
                compressedPublicKey,
                tweak32: tweak,
                format: .compressed
            )
        }
    }
}

extension OpalBase.Cryptography.ECDSA {
    enum Error: Swift.Error {
        case invalidCompressedPublicKeyLength
        case invalidCompressedPublicKeyPrefix
        case invalidDigestLength(expected: Int, actual: Int)
        case invalidHashIterationCount
    }
}

extension OpalBase.Cryptography.ECDSA {
    static func derivePublicKey(from privateKey: Data) throws -> Data {
        try OpalBase.Cryptography.Secp256k1.Operation.derivePublicKey(
            fromPrivateKey32: privateKey,
            format: .compressed
        )
    }
}

extension OpalBase.Cryptography.ECDSA {
    static func sign(
        message: Data,
        with privateKey: OpalBase.PrivateKey,
        in format: OpalBase.Cryptography.SignatureFormat,
        nonceFunction: OpalBase.Cryptography.NoncePolicy = .rfc6979BchDefault
    ) throws -> Data {
        switch format {
        case .ecdsa(let ecdsa):
            let digest32 = SHA256.hash(message)
            let ecdsaSignature = try OpalBase.Cryptography.Secp256k1.sign(
                digest32: digest32,
                privateKey32: privateKey.rawData,
                nonce: makeEcdsaNonce(from: nonceFunction)
            )
            switch ecdsa {
            case .raw:
                return ecdsaSignature.raw64
            case .compact:
                return ecdsaSignature.raw64
            case .der:
                return try ecdsaSignature.encodeDER()
            }
        case .schnorr:
            guard message.count == 32 else {
                throw Error.invalidDigestLength(expected: 32, actual: message.count)
            }
            let signature = try OpalBase.Cryptography.Schnorr.sign(
                digest32: message,
                privateKey32: privateKey.rawData,
                nonce: nonceFunction
            )
            return signature.raw64
        }
    }

    static func sign(
        message: OpalBase.Cryptography.ECDSA.Message,
        with privateKey: OpalBase.PrivateKey,
        in format: OpalBase.Cryptography.SignatureFormat,
        nonceFunction: OpalBase.Cryptography.NoncePolicy = .rfc6979BchDefault
    ) throws -> Data {
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

extension OpalBase.Cryptography.ECDSA {
    static func verify(
        signature: Data,
        message: Data,
        publicKey: OpalBase.PublicKey,
        format: OpalBase.Cryptography.SignatureFormat
    ) throws -> Bool {
        let compressedPublicKey = publicKey.compressedData
        guard compressedPublicKey.count == 33 else { throw Error.invalidCompressedPublicKeyLength }
        let prefix = compressedPublicKey[0]
        guard prefix == 0x02 || prefix == 0x03 else { throw Error.invalidCompressedPublicKeyPrefix }

        switch format {
        case .ecdsa(let ecdsa):
            let digest32 = SHA256.hash(message)
            switch ecdsa {
            case .raw:
                let ecdsaSignature = try OpalBase.Cryptography.Secp256k1.Signature(raw64: signature)
                return try OpalBase.Cryptography.Secp256k1.verify(signature: ecdsaSignature, digest32: digest32, publicKey: compressedPublicKey)
            case .compact:
                let ecdsaSignature = try OpalBase.Cryptography.Secp256k1.Signature(raw64: signature)
                return try OpalBase.Cryptography.Secp256k1.verify(signature: ecdsaSignature, digest32: digest32, publicKey: compressedPublicKey)
            case .der:
                return try OpalBase.Cryptography.Secp256k1.verify(
                    derEncodedSignature: signature,
                    digest32: digest32,
                    publicKey: compressedPublicKey
                )
            }
        case .schnorr:
            do {
                guard message.count == 32 else {
                    throw Error.invalidDigestLength(expected: 32, actual: message.count)
                }
                let schnorrSignature = try OpalBase.Cryptography.Schnorr.Signature(raw64: signature)
                return try OpalBase.Cryptography.Schnorr.verify(
                    signature: schnorrSignature,
                    digest32: message,
                    publicKey: publicKey.compressedData
                )
            } catch {
                return false
            }
        }
    }

    static func verify(
        signature: Data,
        message: OpalBase.Cryptography.ECDSA.Message,
        publicKey: OpalBase.PublicKey,
        format: OpalBase.Cryptography.SignatureFormat
    ) throws -> Bool {
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

extension OpalBase.Cryptography.ECDSA {
    static func detectFormat(signatureCore: Data) -> OpalBase.Cryptography.SignatureFormat? {
        if signatureCore.count == 64 { return .schnorr }
        do {
            _ = try OpalBase.Cryptography.Secp256k1.Signature(derEncoded: signatureCore)
            return .ecdsa(.der)
        } catch {
            return nil
        }
    }
}

private extension OpalBase.Cryptography.ECDSA {
    static func makeEcdsaNonce(
        from nonceFunction: OpalBase.Cryptography.NoncePolicy
    ) -> OpalBase.Cryptography.NoncePolicy.ECDSA {
        switch nonceFunction {
        case .systemRandom:
            return .systemRandom
        case .rfc6979BchDefault, .bipSchnorrDeterministic:
            return .rfc6979Sha256
        }
    }
}
