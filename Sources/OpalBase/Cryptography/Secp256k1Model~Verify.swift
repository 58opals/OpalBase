// Secp256k1Model~Verify.swift

import Foundation

public extension Secp256k1Model {
    static func verify(
        signature: Signature,
        digest32: Data,
        publicKey: Data
    ) throws -> Bool {
        guard digest32.count == 32 else {
            throw Error.invalidDigestLength(actual: digest32.count)
        }
        guard publicKey.count == 33 || publicKey.count == 65 else {
            throw Error.invalidPublicKeyLength(actual: publicKey.count)
        }
        let publicKeyPoint: AffinePointModel
        do {
            publicKeyPoint = try OpalBase.PublicKey.ParsingModel.parsePublicKey(publicKey)
        } catch {
            return false
        }
        let signatureRScalar: ScalarModel
        let signatureSScalar: ScalarModel
        do {
            signatureRScalar = try ScalarModel(data32: signature.r, requireNonZero: true)
            signatureSScalar = try ScalarModel(data32: signature.s, requireNonZero: true)
        } catch {
            return false
        }
        let digestScalar = try ScalarConversionModel.makeReducedScalarFromDigest(digest32)
        let signatureSInverse: ScalarModel
        do {
            signatureSInverse = try signatureSScalar.invert()
        } catch {
            return false
        }
        let u1 = digestScalar.mulModN(signatureSInverse)
        let u2 = signatureRScalar.mulModN(signatureSInverse)
        let u1Point = ScalarMultiplicationModel.mulG(u1)
        let u2Point = ScalarMultiplicationModel.mul(u2, publicKeyPoint)
        let candidatePoint = u1Point.add(u2Point)
        guard let candidateAffine = candidatePoint.convertToAffine() else {
            return false
        }
        guard let candidateScalar = try? ScalarConversionModel.makeScalarFromFieldElement(candidateAffine.x) else {
            return false
        }
        return candidateScalar == signatureRScalar
    }
    
    static func verify(
        derEncodedSignature: Data,
        digest32: Data,
        publicKey: Data
    ) throws -> Bool {
        guard let signature = try? Signature(derEncoded: derEncodedSignature) else {
            return false
        }
        return try verify(signature: signature, digest32: digest32, publicKey: publicKey)
    }
}
