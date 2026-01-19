// Schnorr~Verify.swift

import Foundation

public extension Schnorr {
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
        let signatureRFieldElement: FieldElement
        do {
            signatureRFieldElement = try FieldElement(data32: signature.r)
        } catch {
            return false
        }
        let signatureSScalar: Scalar
        do {
            signatureSScalar = try Scalar(data32: signature.s)
        } catch {
            return false
        }
        let challengeScalar: Scalar
        do {
            challengeScalar = try ChallengeHash.makeChallengeScalar(
                digest32: digest32,
                r: signatureRFieldElement,
                publicKey: publicKeyPoint
            )
        } catch {
            return false
        }
        let sTimesGenerator = ScalarMultiplication.mulG(signatureSScalar)
        let eTimesPublicKey = ScalarMultiplication.mul(challengeScalar, publicKeyPoint)
        let candidatePoint = sTimesGenerator.add(eTimesPublicKey.negate())
        guard !candidatePoint.isInfinity else {
            return false
        }
        let zSquared = candidatePoint.Z.square()
        let expectedX = signatureRFieldElement.mul(zSquared)
        guard candidatePoint.X == expectedX else {
            return false
        }
        let jacobiCandidate = candidatePoint.Y.mul(candidatePoint.Z)
        guard jacobiCandidate.isQuadraticResidue else {
            return false
        }
        return true
    }
}
