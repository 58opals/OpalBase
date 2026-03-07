// ECDSAModel+Error.swift

import Foundation

public struct ECDSAModel {
    static func add(to compressedPublicKey: Data, tweak: Data) throws -> Data {
        try Secp256k1Model.OperationModel.tweakAddPublicKey(compressedPublicKey,
                                                  tweak32: tweak,
                                                  format: .compressed)
    }
}

extension ECDSAModel {
    enum Error: Swift.Error {
        case invalidCompressedPublicKeyLength
        case invalidCompressedPublicKeyPrefix
        case invalidDigestLength(expected: Int, actual: Int)
        case invalidHashIterationCount
    }
}

extension ECDSAModel {
    static func derivePublicKey(from privateKey: Data) throws -> Data {
        try Secp256k1Model.OperationModel.derivePublicKey(fromPrivateKey32: privateKey, format: .compressed)
    }
}

extension ECDSAModel {
    public enum SignatureFormatModel: Sendable {
        /// Signature wire-format used by signing and verification.
        /// - Note:
        ///   - **OP_CHECKSIG + ECDSAModel requires DERModel**. Using `.raw` or `.compact` with CHECKSIG is invalid at consensus.
        ///   - SchnorrModel is allowed for CHECKSIG as per BCH consensus.
        case ecdsa(ECDSAModel)
        case schnorr // Bitcoin Cash SchnorrModel (May 2019+).
        
        public enum ECDSAModel: Sendable {
            case raw
            case compact
            case der
        }
    }
}

extension ECDSAModel {
    static func sign(message: Data,
                     with privateKey: OpalBase.PrivateKey,
                     in format: SignatureFormatModel,
                     nonceFunction: NonceFunctionModel = .rfc6979BchDefault) throws -> Data {
        switch format {
        case .ecdsa(let ecdsa):
            let digest32 = SHA256Model.hash(message)
            let ecdsaSignature = try Secp256k1Model.sign(digest32: digest32,
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
            let signature = try SchnorrModel.sign(digest32: message,
                                             privateKey32: privateKey.rawData,
                                             nonce: nonceFunction)
            return signature.raw64
        }
    }
    
    static func sign(message: ECDSAModel.MessageModel,
                     with privateKey: OpalBase.PrivateKey,
                     in format: SignatureFormatModel,
                     nonceFunction: NonceFunctionModel = .rfc6979BchDefault) throws -> Data {
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

extension ECDSAModel {
    static func verify(signature: Data, message: Data, publicKey: OpalBase.PublicKey, format: SignatureFormatModel) throws -> Bool {
        let compressedPublicKey = publicKey.compressedData
        guard compressedPublicKey.count == 33 else { throw Error.invalidCompressedPublicKeyLength }
        let prefix = compressedPublicKey[0]
        guard prefix == 0x02 || prefix == 0x03 else { throw Error.invalidCompressedPublicKeyPrefix }
        
        switch format {
        case .ecdsa(let ecdsa):
            let digest32 = SHA256Model.hash(message)
            switch ecdsa {
            case .raw:
                let ecdsaSignature = try Secp256k1Model.Signature(raw64: signature)
                return try Secp256k1Model.verify(signature: ecdsaSignature, digest32: digest32, publicKey: compressedPublicKey)
            case .compact:
                let ecdsaSignature = try Secp256k1Model.Signature(raw64: signature)
                return try Secp256k1Model.verify(signature: ecdsaSignature, digest32: digest32, publicKey: compressedPublicKey)
            case .der:
                return try Secp256k1Model.verify(derEncodedSignature: signature,
                                            digest32: digest32,
                                            publicKey: compressedPublicKey)
            }
        case .schnorr:
            do {
                guard message.count == 32 else { throw Error.invalidDigestLength(expected: 32, actual: message.count) }
                let schnorrSignature = try SchnorrModel.Signature(raw64: signature)
                return try SchnorrModel.verify(signature: schnorrSignature,
                                          digest32: message,
                                          publicKey: publicKey.compressedData)
            } catch {
                return false
            }
        }
    }
    
    static func verify(signature: Data, message: ECDSAModel.MessageModel, publicKey: OpalBase.PublicKey, format: SignatureFormatModel) throws -> Bool {
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

extension ECDSAModel {
    static func detectFormat(signatureCore: Data) -> SignatureFormatModel? {
        if signatureCore.count == 64 { return .schnorr }
        do {
            _ = try Secp256k1Model.Signature(derEncoded: signatureCore)
            return .ecdsa(.der)
        } catch {
            return nil
        }
    }
}

private extension ECDSAModel {
    static func makeEcdsaNonce(from nonceFunction: NonceFunctionModel) -> NonceFunctionModel.ECDSAModel {
        switch nonceFunction {
        case .systemRandom:
            return .systemRandom
        case .rfc6979BchDefault, .bipSchnorrDeterministic:
            return .rfc6979Sha256
        }
    }
}

