// ScalarMultiplication+GeneratorPrecompute.swift

import Foundation

extension ScalarMultiplication {
    @usableFromInline static let windowedNonAdjacentFormWidth = 5
    @usableFromInline static let windowedNonAdjacentFormOddMultipleCount = 8
    
    @usableFromInline static let generatorOddMultiplesAffine: InlineArray<8, AffinePoint> = {
        makeOddMultiplesAffineTable(for: generator)
    }()
    
    @usableFromInline static let generatorEndomorphismOddMultiplesAffine: InlineArray<8, AffinePoint> = {
        makeOddMultiplesAffineTable(for: generator.applyEndomorphism())
    }()
    
    private static func makeOddMultiplesAffineTable(for basePoint: AffinePoint) -> InlineArray<8, AffinePoint> {
        var jacobianPoints: [JacobianPoint] = []
        jacobianPoints.reserveCapacity(windowedNonAdjacentFormOddMultipleCount)
        
        let baseJacobian = JacobianPoint(affine: basePoint)
        let doubleBase = baseJacobian.double()
        var accumulator = baseJacobian
        for _ in 0..<windowedNonAdjacentFormOddMultipleCount {
            jacobianPoints.append(accumulator)
            accumulator = accumulator.add(doubleBase)
        }
        
        let affineOptionals = JacobianPoint.convertBatchToAffine(jacobianPoints)
        var affineTable: InlineArray<8, AffinePoint> = .init(repeating: basePoint)
        for index in 0..<windowedNonAdjacentFormOddMultipleCount {
            guard let affinePoint = affineOptionals[index] else {
                preconditionFailure("Unexpected infinity in odd multiple table at index \(index).")
            }
            affineTable[index] = affinePoint
        }
        return affineTable
    }
}
