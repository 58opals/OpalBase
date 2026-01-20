import Foundation
import Testing
@testable import OpalBase

@Suite("Secp256k1 endomorphism", .tags(.unit, .cryptography))
struct Secp256k1EndomorphismTests {
    @Test("Endomorphism preserves curve membership")
    func testEndomorphismPreservesCurveMembership() {
        let generatorPoint = ScalarMultiplication.generator
        let endomorphismPoint = generatorPoint.applyingEndomorphism()
        #expect(generatorPoint.isOnCurve)
        #expect(endomorphismPoint.isOnCurve)
    }
    
    @Test("Endomorphism generator x coordinate matches published value")
    func testEndomorphismGeneratorMatchesPublishedValue() {
        let expectedX = FieldElement(
            unchecked: UInt256(
                limbs: [
                    0xa7bba04400b88fcb,
                    0x872844067f15e98d,
                    0xab0102b696902325,
                    0xbcace2e99da01887
                ]
            )
        )
        let expected = AffinePoint(
            x: expectedX,
            y: FieldElement(unchecked: Secp256k1.Constant.Gy)
        )
        #expect(ScalarMultiplication.generator.applyingEndomorphism() == expected)
    }
    
    @Test("Endomorphism matches scalar lambda multiplication")
    func testEndomorphismMatchesLambdaMultiplication() {
        let lambda = Scalar(unchecked: Secp256k1.Constant.endomorphismLambda)
        let lambdaPoint = ScalarMultiplication.mul(lambda, ScalarMultiplication.generator).toAffine()
        #expect(lambdaPoint == ScalarMultiplication.generator.applyingEndomorphism())
    }
    
    @Test("Scalar split recomposes and stays within expected bounds")
    func testScalarSplitRecomposesAndBounds() throws {
        for seed in 0..<32 {
            let digest = SHA256.hash(Data([UInt8(seed)]))
            let scalar = try ScalarConversion.makeReducedScalarFromDigest(digest)
            let split = scalar.splitForEndomorphism()
            let recomposed = recombine(split: split)
            #expect(recomposed == scalar)
            #expect(isWithin128Bits(split.firstScalar.magnitude))
            #expect(isWithin128Bits(split.secondScalar.magnitude))
        }
    }
    
    @Test("Generator multiplication matches endomorphism path")
    func testGeneratorMultiplicationMatchesEndomorphism() throws {
        for seed in 0..<64 {
            let digest = SHA256.hash(Data([0x42, UInt8(seed)]))
            let scalar = try ScalarConversion.makeReducedScalarFromDigest(digest)
            let endomorphismPoint = ScalarMultiplication.mulGWithEndomorphism(scalar)
            let windowedPoint = ScalarMultiplication.mulGWithEightBitTable(scalar)
            #expect(endomorphismPoint.toAffine() == windowedPoint.toAffine())
        }
    }
    
    private func recombine(
        split: (firstScalar: SignedScalar128, secondScalar: SignedScalar128, isFirstNegative: Bool, isSecondNegative: Bool)
    ) -> Scalar {
        let lambda = Scalar(unchecked: Secp256k1.Constant.endomorphismLambda)
        let firstScalar = makeScalar(from: split.firstScalar)
        let secondScalar = makeScalar(from: split.secondScalar)
        return firstScalar.addModN(secondScalar.mulModN(lambda))
    }
    
    private func makeScalar(from signedScalar: SignedScalar128) -> Scalar {
        let scalar = Scalar(unchecked: signedScalar.magnitude)
        return signedScalar.isNegative ? scalar.negateModN() : scalar
    }
    
    private func isWithin128Bits(_ value: UInt256) -> Bool {
        guard let mostSignificantBitIndex = value.mostSignificantBitIndex else {
            return true
        }
        return mostSignificantBitIndex < 128
    }
}
