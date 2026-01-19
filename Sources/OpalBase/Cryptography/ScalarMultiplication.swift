// ScalarMultiplication.swift

import Foundation

enum ScalarMultiplication {
    private static let generatorMultiples4BitAffine: [AffinePoint] = {
        var jacobianTable = Array(repeating: JacobianPoint.infinity, count: 16)
        jacobianTable[1] = JacobianPoint(affine: generator)
        if jacobianTable.count > 2 {
            for index in 2..<jacobianTable.count {
                jacobianTable[index] = jacobianTable[index - 1].addAffine(generator)
            }
        }
        
        let affineOptionals = JacobianPoint.batchToAffine(jacobianTable)
        var affineTable = Array(repeating: generator, count: 16)
        for index in 1..<affineTable.count {
            guard let affinePoint = affineOptionals[index] else {
                preconditionFailure("Unexpected infinity in generator table at index \(index).")
            }
            affineTable[index] = affinePoint
        }
        return affineTable
    }()
    
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
    
    static func mulG(_ scalar: Scalar) -> JacobianPoint {
        var result = JacobianPoint.infinity
        scalar.forEachBigEndianByte { byte in
            result = result.doubleFourTimes()
            let highHalfByte = Int(byte >> 4)
            if highHalfByte != 0 {
                result = result.addAffine(generatorMultiples4BitAffine[highHalfByte])
            }
            
            result = result.doubleFourTimes()
            let lowHalfByte = Int(byte & 0x0F)
            if lowHalfByte != 0 {
                result = result.addAffine(generatorMultiples4BitAffine[lowHalfByte])
            }
        }
        return result
    }
    
    private static let generator = AffinePoint(
        x: FieldElement(unchecked: Secp256k1.Constant.Gx),
        y: FieldElement(unchecked: Secp256k1.Constant.Gy)
    )
}
