// ScalarMultiplication.swift

import Foundation

enum ScalarMultiplication {
    private static let generatorMultiples4Bit: [JacobianPoint] = {
        var table = Array(repeating: JacobianPoint.infinity, count: 16)
        let generatorPoint = JacobianPoint(affine: generator)
        table[1] = generatorPoint
        if table.count > 2 {
            for index in 2..<table.count {
                table[index] = table[index - 1].add(generatorPoint)
            }
        }
        return table
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
        let bytes = [UInt8](scalar.data32)
        for byte in bytes {
            result = result.double().double().double().double()
            result = result.add(generatorMultiples4Bit[Int(byte >> 4)])
            result = result.double().double().double().double()
            result = result.add(generatorMultiples4Bit[Int(byte & 0x0F)])
        }
        return result
    }
    
    private static let generator = AffinePoint(
        x: FieldElement(unchecked: Secp256k1.Constant.Gx),
        y: FieldElement(unchecked: Secp256k1.Constant.Gy)
    )
}
