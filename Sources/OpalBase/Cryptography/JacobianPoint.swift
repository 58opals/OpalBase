// JacobianPoint.swift

import Foundation

struct JacobianPoint: Sendable, Equatable {
    @usableFromInline let X: FieldElement
    @usableFromInline let Y: FieldElement
    @usableFromInline let Z: FieldElement
    
    @usableFromInline static let infinity = JacobianPoint(X: .zero, Y: .one, Z: .zero)
    
    @inlinable
    var isInfinity: Bool {
        Z.isZero
    }
    
    @inlinable
    init(X: FieldElement, Y: FieldElement, Z: FieldElement) {
        self.X = X
        self.Y = Y
        self.Z = Z
    }
    
    @inlinable
    init(affine: AffinePoint) {
        X = affine.x
        Y = affine.y
        Z = .one
    }
    
    @inlinable
    func convertToAffine() -> AffinePoint? {
        guard !isInfinity else {
            return nil
        }
        let zInverse = Z.invert()
        let zInverseSquared = zInverse.square()
        let x = X.mul(zInverseSquared)
        let y = Y.mul(zInverseSquared.mul(zInverse))
        return AffinePoint(x: x, y: y)
    }
    
    func negate() -> JacobianPoint {
        guard !isInfinity else {
            return self
        }
        return JacobianPoint(X: X, Y: Y.negate(), Z: Z)
    }
    
    @inlinable
    func double() -> JacobianPoint {
        guard !isInfinity, !Y.isZero else {
            return .infinity
        }
        let xCoordinateSquared = X.square()
        let yCoordinateSquared = Y.square()
        let yCoordinateFourth = yCoordinateSquared.square()
        let yCoordinateFourthTimesEight = yCoordinateFourth.double().double().double()
        let xCoordinatePlusYSquared = X.add(yCoordinateSquared)
        let delta = xCoordinatePlusYSquared.square().sub(xCoordinateSquared).sub(yCoordinateFourth).double()
        let threeXCoordinate = xCoordinateSquared.double().add(xCoordinateSquared)
        let xCoordinateResult = threeXCoordinate.square().sub(delta.double())
        let yCoordinateResult = threeXCoordinate.mul(delta.sub(xCoordinateResult)).sub(yCoordinateFourthTimesEight)
        let zCoordinateResult = Y.mul(Z).double()
        return JacobianPoint(X: xCoordinateResult, Y: yCoordinateResult, Z: zCoordinateResult)
    }
    
    @inlinable
    func doubleFourTimes() -> JacobianPoint {
        var result = self
        result = result.double()
        result = result.double()
        result = result.double()
        result = result.double()
        return result
    }
    
    @inlinable
    func doubleEightTimes() -> JacobianPoint {
        var result = self
        result = result.double()
        result = result.double()
        result = result.double()
        result = result.double()
        result = result.double()
        result = result.double()
        result = result.double()
        result = result.double()
        return result
    }
    
    @inlinable
    func add(_ other: JacobianPoint) -> JacobianPoint {
        guard !isInfinity else {
            return other
        }
        guard !other.isInfinity else {
            return self
        }
        
        let firstZSquared = Z.square()
        let secondZSquared = other.Z.square()
        let firstXAdjusted = X.mul(secondZSquared)
        let secondXAdjusted = other.X.mul(firstZSquared)
        let firstZCubed = firstZSquared.mul(Z)
        let secondZCubed = secondZSquared.mul(other.Z)
        let firstYAdjusted = Y.mul(secondZCubed)
        let secondYAdjusted = other.Y.mul(firstZCubed)
        
        if firstXAdjusted == secondXAdjusted {
            if firstYAdjusted != secondYAdjusted {
                return .infinity
            }
            return double()
        }
        
        let xDifference = secondXAdjusted.sub(firstXAdjusted)
        let xDifferenceSquared = xDifference.double().square()
        let xDifferenceCubed = xDifference.mul(xDifferenceSquared)
        let yDifference = secondYAdjusted.sub(firstYAdjusted).double()
        let firstProduct = firstXAdjusted.mul(xDifferenceSquared)
        let xCoordinateResult = yDifference.square().sub(xDifferenceCubed).sub(firstProduct.double())
        let yCoordinateResult = yDifference.mul(firstProduct.sub(xCoordinateResult)).sub(firstYAdjusted.mul(xDifferenceCubed).double())
        let zCoordinateResult = Z.add(other.Z).square().sub(firstZSquared).sub(secondZSquared).mul(xDifference)
        return JacobianPoint(X: xCoordinateResult, Y: yCoordinateResult, Z: zCoordinateResult)
    }
    
    @inlinable
    func addAffine(_ other: AffinePoint) -> JacobianPoint {
        guard !isInfinity else {
            return JacobianPoint(affine: other)
        }
        
        let zSquared = Z.square()
        let otherXAdjusted = other.x.mul(zSquared)
        let otherYAdjusted = other.y.mul(zSquared.mul(Z))
        let xDifference = otherXAdjusted.sub(X)
        let yDifference = otherYAdjusted.sub(Y)
        
        if xDifference.isZero {
            return yDifference.isZero ? double() : .infinity
        }
        
        let xDifferenceSquared = xDifference.square()
        let xDifferenceCubed = xDifference.mul(xDifferenceSquared)
        let xProduct = X.mul(xDifferenceSquared)
        
        let xCoordinateResult = yDifference.square().sub(xDifferenceCubed).sub(xProduct.double())
        let yCoordinateResult = yDifference.mul(xProduct.sub(xCoordinateResult)).sub(Y.mul(xDifferenceCubed))
        let zCoordinateResult = Z.mul(xDifference)
        return JacobianPoint(X: xCoordinateResult, Y: yCoordinateResult, Z: zCoordinateResult)
    }
    
    static func convertBatchToAffine(_ points: [JacobianPoint]) -> [AffinePoint?] {
        let temporaryAllocationThreshold = 64
        var pointIndices: [Int] = .init()
        pointIndices.reserveCapacity(points.count)
        for index in points.indices where !points[index].isInfinity {
            pointIndices.append(index)
        }
        
        var results = Array<AffinePoint?>(repeating: nil, count: points.count)
        guard !pointIndices.isEmpty else { return results }
        
        if pointIndices.count <= temporaryAllocationThreshold {
            return withUnsafeTemporaryAllocation(of: FieldElement.self, capacity: pointIndices.count) { prefixProducts in
                var productAccumulator = FieldElement.one
                for (position, index) in pointIndices.enumerated() {
                    productAccumulator = productAccumulator.mul(points[index].Z)
                    prefixProducts[position] = productAccumulator
                }
                
                var inverseAccumulator = productAccumulator.invert()
                
                for position in pointIndices.indices.reversed() {
                    let pointIndex = pointIndices[position]
                    let zCoordinate = points[pointIndex].Z
                    let prefixProduct = position == pointIndices.startIndex ? FieldElement.one : prefixProducts[position - 1]
                    
                    let zCoordinateInverse = inverseAccumulator.mul(prefixProduct)
                    inverseAccumulator = inverseAccumulator.mul(zCoordinate)
                    
                    let zCoordinateInverseSquared = zCoordinateInverse.square()
                    let x = points[pointIndex].X.mul(zCoordinateInverseSquared)
                    let y = points[pointIndex].Y.mul(zCoordinateInverseSquared.mul(zCoordinateInverse))
                    results[pointIndex] = AffinePoint(x: x, y: y)
                }
                
                return results
            }
        }
        
        var prefixProducts: [FieldElement] = .init()
        prefixProducts.reserveCapacity(pointIndices.count)
        var productAccumulator = FieldElement.one
        for index in pointIndices {
            productAccumulator = productAccumulator.mul(points[index].Z)
            prefixProducts.append(productAccumulator)
        }
        
        var inverseAccumulator = productAccumulator.invert()
        
        for position in pointIndices.indices.reversed() {
            let pointIndex = pointIndices[position]
            let zCoordinate = points[pointIndex].Z
            let prefixProduct = position == pointIndices.startIndex ? FieldElement.one : prefixProducts[position - 1]
            
            let zCoordinateInverse = inverseAccumulator.mul(prefixProduct)
            inverseAccumulator = inverseAccumulator.mul(zCoordinate)
            
            let zCoordinateInverseSquared = zCoordinateInverse.square()
            let x = points[pointIndex].X.mul(zCoordinateInverseSquared)
            let y = points[pointIndex].Y.mul(zCoordinateInverseSquared.mul(zCoordinateInverse))
            results[pointIndex] = AffinePoint(x: x, y: y)
        }
        
        return results
    }
}
