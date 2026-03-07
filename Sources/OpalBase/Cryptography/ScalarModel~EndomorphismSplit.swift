// ScalarModel~EndomorphismSplit.swift

import Foundation

extension ScalarModel {
    func splitForEndomorphism() -> (firstScalar: SignedScalar128Model, secondScalar: SignedScalar128Model, isFirstNegative: Bool, isSecondNegative: Bool) {
        let coefficientOne = Secp256k1Model.ConstantModel.endomorphismCoefficientOne
        let coefficientTwo = Secp256k1Model.ConstantModel.endomorphismCoefficientTwo
        let minusBasisOne = Secp256k1Model.ConstantModel.endomorphismMinusBasisOne
        let minusBasisTwo = Secp256k1Model.ConstantModel.endomorphismMinusBasisTwo
        let lambda = ScalarModel(unchecked: Secp256k1Model.ConstantModel.endomorphismLambda)
        
        let coefficientOneProduct = ScalarModel(unchecked: value.multiplyShiftRight384(by: coefficientOne))
        let coefficientTwoProduct = ScalarModel(unchecked: value.multiplyShiftRight384(by: coefficientTwo))
        
        let minusBasisOneScalar = ScalarModel(unchecked: minusBasisOne)
        let minusBasisTwoScalar = ScalarModel(unchecked: minusBasisTwo)
        
        let secondScalar = coefficientOneProduct.mulModN(minusBasisOneScalar)
            .addModN(coefficientTwoProduct.mulModN(minusBasisTwoScalar))
        let firstScalar = subModN(secondScalar.mulModN(lambda))
        
        let signedFirstScalar = ScalarModel.makeSignedScalar128(from: firstScalar)
        let signedSecondScalar = ScalarModel.makeSignedScalar128(from: secondScalar)
        
        return (signedFirstScalar, signedSecondScalar, signedFirstScalar.isNegative, signedSecondScalar.isNegative)
    }
}

private extension ScalarModel {
    static func makeSignedScalar128(from scalar: ScalarModel) -> SignedScalar128Model {
        let isNegative = scalar.compare(to: Secp256k1Model.halfOrderScalar) == .orderedDescending
        let magnitude = isNegative ? scalar.negateModN() : scalar
        return SignedScalar128Model(magnitude: magnitude.value, isNegative: isNegative)
    }
}

private extension UInt256Model {
    func multiplyShiftRight384(by other: UInt256Model) -> UInt256Model {
        var product = multiplyFullWidth(by: other)
        let roundingBit: UInt64 = 1 << 63
        let (roundedLimb, carryFromRounding) = product.limbs[5].addingReportingOverflow(roundingBit)
        product.limbs[5] = roundedLimb
        if carryFromRounding {
            let (limbSixSum, carryIntoLimbSeven) = product.limbs[6].addingReportingOverflow(1)
            product.limbs[6] = limbSixSum
            if carryIntoLimbSeven {
                product.limbs[7] &+= 1
            }
        }
        return UInt256Model(limbs: [product.limbs[6], product.limbs[7], 0, 0])
    }
}

