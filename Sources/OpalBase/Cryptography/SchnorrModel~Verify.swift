// SchnorrModel~Verify.swift

import Foundation

public extension SchnorrModel {
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
            publicKeyPoint = try PublicKeyModel.ParsingModel.parsePublicKey(publicKey)
        } catch {
            return false
        }
        let signatureRFieldElement: FieldElementModel
        do {
            signatureRFieldElement = try FieldElementModel(data32: signature.r)
        } catch {
            return false
        }
        let signatureSScalar: ScalarModel
        do {
            signatureSScalar = try ScalarModel(data32: signature.s)
        } catch {
            return false
        }
        let challengeScalar: ScalarModel
        do {
            challengeScalar = try ChallengeHashModel.makeChallengeScalar(
                digest32: digest32,
                r: signatureRFieldElement,
                publicKey: publicKeyPoint
            )
        } catch {
            return false
        }
        let sTimesGenerator = ScalarMultiplicationModel.mulG(signatureSScalar)
        let eTimesPublicKey = ScalarMultiplicationModel.mul(challengeScalar, publicKeyPoint)
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
