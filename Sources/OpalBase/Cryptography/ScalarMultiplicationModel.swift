// ScalarMultiplicationModel.swift

import Foundation

enum ScalarMultiplicationModel {
    @usableFromInline static let generatorMultiples8BitAffineCalculation: InlineArray<256, AffinePointModel> = {
        var jacobianTable = Array(repeating: JacobianPointModel.infinity, count: 256)
        jacobianTable[1] = JacobianPointModel(affine: generator)
        if jacobianTable.count > 2 {
            for index in 2..<jacobianTable.count {
                jacobianTable[index] = jacobianTable[index - 1].addAffine(generator)
            }
        }
        
        let affineOptionals = JacobianPointModel.convertBatchToAffine(jacobianTable)
        var affineTable: InlineArray<256, AffinePointModel> = .init(repeating: generator)
        for index in 1..<256 {
            guard let affinePoint = affineOptionals[index] else {
                preconditionFailure("Unexpected infinity in generator table at index \(index).")
            }
            affineTable[index] = affinePoint
        }
        return affineTable
    }()
    
    @inlinable
    static func mul(_ scalar: ScalarModel, _ point: AffinePointModel) -> JacobianPointModel {
        var resultZero = JacobianPointModel.infinity
        var resultOne = JacobianPointModel(affine: point)
        for index in stride(from: 255, through: 0, by: -1) {
            if scalar.testBit(at: index) {
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
    static func mulG(_ scalar: ScalarModel) -> JacobianPointModel {
        if CryptoTuningModel.shouldUseEndomorphismForGeneratorMultiplication {
            return mulGWithEndomorphism(scalar)
        }
        return mulGWithEightBitTable(scalar)
    }
    
    @inlinable
    static func mulGWithEightBitTable(_ scalar: ScalarModel) -> JacobianPointModel {
        var result = JacobianPointModel.infinity
        for limbIndex in stride(from: 3, through: 0, by: -1) {
            let limb = scalar.limbs[limbIndex]
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
    
    @usableFromInline static let generator = AffinePointModel(
        x: FieldElementModel(unchecked: Secp256k1Model.ConstantModel.Gx),
        y: FieldElementModel(unchecked: Secp256k1Model.ConstantModel.Gy)
    )
}
