// JacobianPointModel.swift

import Foundation

struct JacobianPointModel: Sendable, Equatable {
    @usableFromInline let X: FieldElementModel
    @usableFromInline let Y: FieldElementModel
    @usableFromInline let Z: FieldElementModel

    @usableFromInline static let infinity = JacobianPointModel(X: .zero, Y: .one, Z: .zero)

    @inlinable
    var isInfinity: Bool {
        Z.isZero
    }

    @inlinable
    init(X: FieldElementModel, Y: FieldElementModel, Z: FieldElementModel) {
        self.X = X
        self.Y = Y
        self.Z = Z
    }

    @inlinable
    init(affine: AffinePointModel) {
        X = affine.x
        Y = affine.y
        Z = .one
    }

    @inlinable
    func convertToAffine() -> AffinePointModel? {
        guard !isInfinity else {
            return nil
        }
        let zInverse = Z.invert()
        let zInverseSquared = zInverse.square()
        let x = X.mul(zInverseSquared)
        let y = Y.mul(zInverseSquared.mul(zInverse))
        return AffinePointModel(x: x, y: y)
    }

    func negate() -> JacobianPointModel {
        guard !isInfinity else {
            return self
        }
        return JacobianPointModel(X: X, Y: Y.negate(), Z: Z)
    }
}
