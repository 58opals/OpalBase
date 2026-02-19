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
}
