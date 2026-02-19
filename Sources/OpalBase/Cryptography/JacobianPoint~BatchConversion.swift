// JacobianPoint~BatchConversion.swift

import Foundation

extension JacobianPoint {
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
