// OpalBase.Cryptography.Secp256k1+Operation.swift

import Foundation

extension OpalBase.Cryptography.Secp256k1 {
    public enum Operation {
        public enum PublicKeyFormat {
            case compressed
            case uncompressed
        }

        public enum Error: Swift.Error, Equatable {
            case invalidPrivateKeyLength(actual: Int)
            case invalidPrivateKeyValue
            case invalidPublicKeyLength(actual: Int)
            case invalidPublicKeyValue
            case invalidTweakLength(actual: Int)
            case invalidTweakValue
            case invalidDerivedPrivateKey
            case invalidDerivedPublicKey
        }

        public static var curveOrderN: Data {
            OpalBase.Cryptography.Secp256k1.Constant.n.data32
        }

        public static func validatePrivateKey32(_ privateKey32: Data) -> Bool {
            (try? Scalar(data32: privateKey32, requireNonZero: true)) != nil
        }

        public static func derivePublicKey(
            fromPrivateKey32 privateKey32: Data,
            format: PublicKeyFormat = .compressed
        ) throws -> Data {
            let privateKeyScalar = try parsePrivateKeyScalar(privateKey32, requireNonZero: true)
            let publicPoint = ScalarMultiplication.mulG(privateKeyScalar)
            guard let publicAffine = publicPoint.convertToAffine() else {
                throw Error.invalidDerivedPublicKey
            }
            return encodePublicKey(publicAffine, format: format)
        }

        public static func tweakAddPrivateKey32(
            _ privateKey32: Data,
            tweak32: Data
        ) throws -> Data {
            let privateKeyScalar = try parsePrivateKeyScalar(privateKey32, requireNonZero: true)
            let tweakScalar = try parseTweakScalar(tweak32, requireNonZero: false)
            let derivedScalar = privateKeyScalar.addModN(tweakScalar)
            guard !derivedScalar.isZero else {
                throw Error.invalidDerivedPrivateKey
            }
            return derivedScalar.data32
        }

        public static func tweakAddPublicKey(
            _ publicKey: Data,
            tweak32: Data,
            format: PublicKeyFormat? = nil
        ) throws -> Data {
            let publicAffine = try parsePublicKeyAffine(publicKey)
            let tweakScalar = try parseTweakScalar(tweak32, requireNonZero: true)
            let tweakPoint = ScalarMultiplication.mulG(tweakScalar)
            let combined = JacobianPoint(affine: publicAffine).add(tweakPoint)
            guard let derivedAffine = combined.convertToAffine() else {
                throw Error.invalidDerivedPublicKey
            }
            let resolvedFormat = try resolveFormat(from: publicKey, format: format)
            return encodePublicKey(derivedAffine, format: resolvedFormat)
        }
    }
}
