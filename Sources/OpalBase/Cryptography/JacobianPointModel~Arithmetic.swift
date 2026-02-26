// JacobianPointModel~Arithmetic.swift

import Foundation

extension JacobianPointModel {
    @inlinable
    func double() -> JacobianPointModel {
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
        return JacobianPointModel(X: xCoordinateResult, Y: yCoordinateResult, Z: zCoordinateResult)
    }

    @inlinable
    func doubleFourTimes() -> JacobianPointModel {
        var result = self
        result = result.double()
        result = result.double()
        result = result.double()
        result = result.double()
        return result
    }

    @inlinable
    func doubleEightTimes() -> JacobianPointModel {
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
    func add(_ other: JacobianPointModel) -> JacobianPointModel {
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
        return JacobianPointModel(X: xCoordinateResult, Y: yCoordinateResult, Z: zCoordinateResult)
    }

    @inlinable
    func addAffine(_ other: AffinePointModel) -> JacobianPointModel {
        guard !isInfinity else {
            return JacobianPointModel(affine: other)
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
        return JacobianPointModel(X: xCoordinateResult, Y: yCoordinateResult, Z: zCoordinateResult)
    }
}
