// ScalarMultiplication.swift

import Foundation

enum ScalarMultiplication {
    @usableFromInline static let generatorMultiples8BitAffine: InlineArray<256, AffinePoint> = {
        var jacobianTable = Array(repeating: JacobianPoint.infinity, count: 256)
        jacobianTable[1] = JacobianPoint(affine: generator)
        if jacobianTable.count > 2 {
            for index in 2..<jacobianTable.count {
                jacobianTable[index] = jacobianTable[index - 1].addAffine(generator)
            }
        }
        
        let affineOptionals = JacobianPoint.batchToAffine(jacobianTable)
        var affineTable: InlineArray<256, AffinePoint> = .init(repeating: generator)
        for index in 1..<256 {
            guard let affinePoint = affineOptionals[index] else {
                preconditionFailure("Unexpected infinity in generator table at index \(index).")
            }
            affineTable[index] = affinePoint
        }
        return affineTable
    }()
    
    @inlinable
    static func mul(_ scalar: Scalar, _ point: AffinePoint) -> JacobianPoint {
        var resultZero = JacobianPoint.infinity
        var resultOne = JacobianPoint(affine: point)
        for index in stride(from: 255, through: 0, by: -1) {
            if scalar.bit(at: index) {
                resultZero = resultZero.add(resultOne)
                resultOne = resultOne.double()
            } else {
                resultOne = resultZero.add(resultOne)
                resultZero = resultZero.double()
            }
        }
        return resultZero
    }
    
    @inlinable
    static func mulG(_ scalar: Scalar) -> JacobianPoint {
        var result = JacobianPoint.infinity
        for limbIndex in stride(from: 3, through: 0, by: -1) {
            let limb = scalar.limbs[limbIndex].bigEndian
            for shift in stride(from: 56, through: 0, by: -8) {
                result = result.doubleEightTimes()
                let byteValue = Int((limb >> shift) & 0xff)
                if byteValue != 0 {
                    result = result.addAffine(generatorMultiples8BitAffine[byteValue])
                }
            }
        }
        return result
    }
    
    @usableFromInline static let generator = AffinePoint(
        x: FieldElement(unchecked: Secp256k1.Constant.Gx),
        y: FieldElement(unchecked: Secp256k1.Constant.Gy)
    )
}
