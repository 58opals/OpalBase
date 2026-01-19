// Schnorr~Sign.swift

import Foundation

public extension Schnorr {
    static func sign(
        digest32: Data,
        privateKey32: Data,
        nonce: NonceFunction = .rfc6979BchDefault
    ) throws -> Signature {
        guard digest32.count == 32 else {
            throw Error.invalidDigestLength(actual: digest32.count)
        }
        guard privateKey32.count == 32 else {
            throw Error.invalidPrivateKeyLength(actual: privateKey32.count)
        }
        let privateKeyScalar: Scalar
        do {
            privateKeyScalar = try Scalar(data32: privateKey32, requireNonZero: true)
        } catch {
            throw Error.invalidPrivateKeyValue
        }
        let publicKeyPoint = ScalarMultiplication.mulG(privateKeyScalar)
        guard let publicKeyAffine = publicKeyPoint.toAffine() else {
            throw Error.invalidPrivateKeyValue
        }
        var makeNextNonce: () throws -> Scalar
        switch nonce {
        case .rfc6979BchDefault:
            var generator = try NonceGenerator(privateKey: privateKeyScalar, digest32: digest32)
            makeNextNonce = {
                try generator.makeNextScalar()
            }
        case .bipSchnorrDeterministic:
            var generator = try NonceGenerator.BIPSchnorr(
                privateKey: privateKeyScalar,
                digest32: digest32
            )
            makeNextNonce = {
                try generator.makeNextScalar()
            }
        case .systemRandom:
            makeNextNonce = {
                try makeSystemRandomScalar()
            }
        }
        while true {
            let nonceScalar = try makeNextNonce()
            let noncePoint = ScalarMultiplication.mulG(nonceScalar)
            let jacobiCandidate = noncePoint.Y.mul(noncePoint.Z)
            let adjustedNonceScalar: Scalar
            let adjustedNoncePoint: JacobianPoint
            if jacobiCandidate.isQuadraticResidue {
                adjustedNonceScalar = nonceScalar
                adjustedNoncePoint = noncePoint
            } else {
                adjustedNonceScalar = nonceScalar.negateModN()
                adjustedNoncePoint = noncePoint.negate()
            }
            guard let adjustedNonceAffine = adjustedNoncePoint.toAffine() else {
                continue
            }
            let signatureRFieldElement = adjustedNonceAffine.x
            let challengeScalar = try ChallengeHash.makeChallengeScalar(
                digest32: digest32,
                r: signatureRFieldElement,
                publicKey: publicKeyAffine
            )
            let product = challengeScalar.mulModN(privateKeyScalar)
            let signatureSScalar = adjustedNonceScalar.addModN(product)
            guard !signatureSScalar.isZero else {
                continue
            }
            return try Signature(
                r: signatureRFieldElement.data32,
                s: signatureSScalar.data32
            )
        }
    }
}
