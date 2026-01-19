// Secp256k1~Verify.swift

import Foundation

public extension Secp256k1 {
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
        let publicKeyPoint: AffinePoint
        do {
            publicKeyPoint = try PublicKey.Parsing.parsePublicKey(publicKey)
        } catch {
            return false
        }
        let signatureRScalar: Scalar
        let signatureSScalar: Scalar
        do {
            signatureRScalar = try Scalar(data32: signature.r, requireNonZero: true)
            signatureSScalar = try Scalar(data32: signature.s, requireNonZero: true)
        } catch {
            return false
        }
        let digestScalar = try ScalarConversion.makeReducedScalarFromDigest(digest32)
        let signatureSInverse: Scalar
        do {
            signatureSInverse = try signatureSScalar.invert()
        } catch {
            return false
        }
        let u1 = digestScalar.mulModN(signatureSInverse)
        let u2 = signatureRScalar.mulModN(signatureSInverse)
        let u1Point = ScalarMultiplication.mulG(u1)
        let u2Point = ScalarMultiplication.mul(u2, publicKeyPoint)
        let candidatePoint = u1Point.add(u2Point)
        guard let candidateAffine = candidatePoint.toAffine() else {
            return false
        }
        guard let candidateScalar = try? ScalarConversion.makeScalarFromFieldElement(candidateAffine.x) else {
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
