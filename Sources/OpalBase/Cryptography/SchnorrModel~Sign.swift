// SchnorrModel~Sign.swift

import Foundation

public extension SchnorrModel {
    static func sign(
        digest32: Data,
        privateKey32: Data,
        nonce: NonceFunctionModel = .rfc6979BchDefault
    ) throws -> Signature {
        guard digest32.count == 32 else {
            throw Error.invalidDigestLength(actual: digest32.count)
        }
        guard privateKey32.count == 32 else {
            throw Error.invalidPrivateKeyLength(actual: privateKey32.count)
        }
        let privateKeyScalar: ScalarModel
        do {
            privateKeyScalar = try ScalarModel(data32: privateKey32, requireNonZero: true)
        } catch {
            throw Error.invalidPrivateKeyValue
        }
        let publicKeyPoint = ScalarMultiplicationModel.mulG(privateKeyScalar)
        guard let publicKeyAffine = publicKeyPoint.convertToAffine() else {
            throw Error.invalidPrivateKeyValue
        }
        var makeNextNonce: () throws -> ScalarModel
        switch nonce {
        case .rfc6979BchDefault:
            var generator = try NonceGeneratorModel(privateKey: privateKeyScalar, digest32: digest32)
            makeNextNonce = {
                try generator.makeNextScalar()
            }
        case .bipSchnorrDeterministic:
            var generator = try NonceGeneratorModel.BIPSchnorr(
                privateKey: privateKeyScalar,
                digest32: digest32
            )
            makeNextNonce = {
                try generator.makeNextScalar()
            }
        case .systemRandom:
            makeNextNonce = {
                try NonceGeneratorModel.makeSystemRandomScalar()
            }
        }
        while true {
            let nonceScalar = try makeNextNonce()
            let noncePoint = ScalarMultiplicationModel.mulG(nonceScalar)
            let jacobiCandidate = noncePoint.Y.mul(noncePoint.Z)
            let adjustedNonceScalar: ScalarModel
            let adjustedNoncePoint: JacobianPointModel
            if jacobiCandidate.isQuadraticResidue {
                adjustedNonceScalar = nonceScalar
                adjustedNoncePoint = noncePoint
            } else {
                adjustedNonceScalar = nonceScalar.negateModN()
                adjustedNoncePoint = noncePoint.negate()
            }
            guard let adjustedNonceAffine = adjustedNoncePoint.convertToAffine() else {
                continue
            }
            let signatureRFieldElement = adjustedNonceAffine.x
            let challengeScalar = try ChallengeHashModel.makeChallengeScalar(
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
