// Secp256k1EndomorphismValidator.swift

import Foundation
import Testing
import OpalBaseTestSupport
@testable import OpalBase

@Suite("OpalBase.Cryptography.Secp256k1 endomorphism", .tags(.unit, .cryptography))
struct Secp256k1EndomorphismValidator {
    @Test("Endomorphism preserves curve membership")
    func endomorphismPreservesCurveMembership() {
        let generatorPoint = ScalarMultiplicationModel.generator
        let endomorphismPoint = generatorPoint.applyEndomorphism()
        #expect(generatorPoint.isOnCurve)
        #expect(endomorphismPoint.isOnCurve)
    }
    
    @Test("Endomorphism generator x coordinate matches published value")
    func endomorphismGeneratorMatchesPublishedValue() {
        let expectedX = FieldElementModel(
            unchecked: UInt256Model(
                limbs: [
                    0xa7bba04400b88fcb,
                    0x872844067f15e98d,
                    0xab0102b696902325,
                    0xbcace2e99da01887
                ]
            )
        )
        let expected = AffinePointModel(
            x: expectedX,
            y: FieldElementModel(unchecked: OpalBase.Cryptography.Secp256k1.Constant.Gy)
        )
        #expect(ScalarMultiplicationModel.generator.applyEndomorphism() == expected)
    }
    
    @Test("Endomorphism matches scalar lambda multiplication")
    func endomorphismMatchesLambdaMultiplication() {
        let lambda = ScalarModel(unchecked: OpalBase.Cryptography.Secp256k1.Constant.endomorphismLambda)
        let lambdaPoint = ScalarMultiplicationModel.mul(lambda, ScalarMultiplicationModel.generator).convertToAffine()
        #expect(lambdaPoint == ScalarMultiplicationModel.generator.applyEndomorphism())
    }
    
    @Test("ScalarModel split recomposes and stays within expected bounds")
    func scalarSplitRecomposesAndBounds() throws {
        for seed in 0..<32 {
            let digest = SHA256Model.hash(Data([UInt8(seed)]))
            let scalar = try ScalarConversionModel.makeReducedScalarFromDigest(digest)
            let split = scalar.splitForEndomorphism()
            let recomposed = recombine(split: split)
            #expect(recomposed == scalar)
            #expect(isWithin128Bits(split.firstScalar.magnitude))
            #expect(isWithin128Bits(split.secondScalar.magnitude))
        }
    }
    
    @Test("Generator multiplication matches endomorphism path")
    func generatorMultiplicationMatchesEndomorphism() throws {
        for seed in 0..<64 {
            let digest = SHA256Model.hash(Data([0x42, UInt8(seed)]))
            let scalar = try ScalarConversionModel.makeReducedScalarFromDigest(digest)
            let endomorphismPoint = ScalarMultiplicationModel.mulGWithEndomorphism(scalar)
            let windowedPoint = ScalarMultiplicationModel.mulGWithEightBitTable(scalar)
            #expect(endomorphismPoint.convertToAffine() == windowedPoint.convertToAffine())
        }
    }
    
    private func recombine(
        split: (firstScalar: SignedScalar128Model, secondScalar: SignedScalar128Model, isFirstNegative: Bool, isSecondNegative: Bool)
    ) -> ScalarModel {
        let lambda = ScalarModel(unchecked: OpalBase.Cryptography.Secp256k1.Constant.endomorphismLambda)
        let firstScalar = makeScalar(from: split.firstScalar)
        let secondScalar = makeScalar(from: split.secondScalar)
        return firstScalar.addModN(secondScalar.mulModN(lambda))
    }
    
    private func makeScalar(from signedScalar: SignedScalar128Model) -> ScalarModel {
        let scalar = ScalarModel(unchecked: signedScalar.magnitude)
        return signedScalar.isNegative ? scalar.negateModN() : scalar
    }
    
    private func isWithin128Bits(_ value: UInt256Model) -> Bool {
        guard let mostSignificantBitIndex = value.mostSignificantBitIndex else {
            return true
        }
        return mostSignificantBitIndex < 128
    }
}

