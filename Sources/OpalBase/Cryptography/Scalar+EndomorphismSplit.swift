// Scalar+EndomorphismSplit.swift

import Foundation

extension Scalar {
    func splitForEndomorphism() -> (firstScalar: SignedScalar128, secondScalar: SignedScalar128, isFirstNegative: Bool, isSecondNegative: Bool) {
        let coefficientOne = Secp256k1.Constant.endomorphismCoefficientOne
        let coefficientTwo = Secp256k1.Constant.endomorphismCoefficientTwo
        let minusBasisOne = Secp256k1.Constant.endomorphismMinusBasisOne
        let minusBasisTwo = Secp256k1.Constant.endomorphismMinusBasisTwo
        let lambda = Scalar(unchecked: Secp256k1.Constant.endomorphismLambda)
        
        let coefficientOneProduct = Scalar(unchecked: value.multiplyShiftRight384(by: coefficientOne))
        let coefficientTwoProduct = Scalar(unchecked: value.multiplyShiftRight384(by: coefficientTwo))
        
        let minusBasisOneScalar = Scalar(unchecked: minusBasisOne)
        let minusBasisTwoScalar = Scalar(unchecked: minusBasisTwo)
        
        let secondScalar = coefficientOneProduct.mulModN(minusBasisOneScalar)
            .addModN(coefficientTwoProduct.mulModN(minusBasisTwoScalar))
        let firstScalar = subModN(secondScalar.mulModN(lambda))
        
        let signedFirstScalar = Scalar.makeSignedScalar128(from: firstScalar)
        let signedSecondScalar = Scalar.makeSignedScalar128(from: secondScalar)
        
        return (signedFirstScalar, signedSecondScalar, signedFirstScalar.isNegative, signedSecondScalar.isNegative)
    }
}

private extension Scalar {
    static func makeSignedScalar128(from scalar: Scalar) -> SignedScalar128 {
        let isNegative = scalar.compare(to: Secp256k1.halfOrderScalar) == .orderedDescending
        let magnitude = isNegative ? scalar.negateModN() : scalar
        return SignedScalar128(magnitude: magnitude.value, isNegative: isNegative)
    }
}

private extension UInt256 {
    func multiplyShiftRight384(by other: UInt256) -> UInt256 {
        let product = multipliedFullWidth(by: other)
        return UInt256(limbs: [product.limbs[6], product.limbs[7], 0, 0])
    }
}
