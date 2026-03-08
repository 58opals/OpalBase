// FieldElementModel.swift

import Foundation

struct FieldElementModel: Sendable, Equatable {
    enum Error: Swift.Error, Equatable {
        case invalidFieldValue
        case invalidDataLength(expected: Int, actual: Int)
    }
    
    @usableFromInline let value: UInt256Model
    
    @usableFromInline static let zero = FieldElementModel(unchecked: UInt256Model(limbs: [0, 0, 0, 0]))
    @usableFromInline static let one = FieldElementModel(unchecked: UInt256Model(limbs: [1, 0, 0, 0]))
    @usableFromInline static let two = FieldElementModel(unchecked: UInt256Model(limbs: [2, 0, 0, 0]))
    @usableFromInline static let three = FieldElementModel(unchecked: UInt256Model(limbs: [3, 0, 0, 0]))
    @usableFromInline static let seven = FieldElementModel(unchecked: UInt256Model(limbs: [7, 0, 0, 0]))
    @usableFromInline static let eight = FieldElementModel(unchecked: UInt256Model(limbs: [8, 0, 0, 0]))
    
    init(value: UInt256Model) throws {
        guard value.compare(to: OpalBase.Cryptography.Secp256k1.Constant.p) == .orderedAscending else {
            throw Error.invalidFieldValue
        }
        self.value = value
    }
    
    init(data32: Data) throws {
        guard data32.count == 32 else {
            throw Error.invalidDataLength(expected: 32, actual: data32.count)
        }
        let parsed = try UInt256Model(data32: data32)
        try self.init(value: parsed)
    }
    
    @inlinable
    func add(_ other: FieldElementModel) -> FieldElementModel {
        let (sum, carry) = value.add(other.value)
        var reduced = sum
        if carry || reduced.compare(to: OpalBase.Cryptography.Secp256k1.Constant.p) != .orderedAscending {
            reduced = reduced.subtract(OpalBase.Cryptography.Secp256k1.Constant.p).difference
        }
        return FieldElementModel(unchecked: reduced)
    }
    
    @inlinable
    func sub(_ other: FieldElementModel) -> FieldElementModel {
        let (difference, borrow) = value.subtract(other.value)
        var reduced = difference
        if borrow {
            reduced = reduced.add(OpalBase.Cryptography.Secp256k1.Constant.p).sum
        }
        return FieldElementModel(unchecked: reduced)
    }
    
    @inlinable
    func negate() -> FieldElementModel {
        guard !value.isZero else {
            return .zero
        }
        let difference = OpalBase.Cryptography.Secp256k1.Constant.p.subtract(value).difference
        return FieldElementModel(unchecked: difference)
    }
    
    @inlinable
    func mul(_ other: FieldElementModel) -> FieldElementModel {
        let product = value.multiplyFullWidth(by: other.value)
        let reduced = FieldReductionModel.reduce(product)
        return FieldElementModel(unchecked: reduced)
    }
    
    @inlinable
    func square() -> FieldElementModel {
        let product = value.squareFullWidth()
        let reduced = FieldReductionModel.reduce(product)
        return FieldElementModel(unchecked: reduced)
    }
    
    @inlinable
    func double() -> FieldElementModel {
        add(self)
    }
    
    var isQuadraticResidue: Bool {
        pow(exponentBits: FieldPowModel.legendreExponentBits) == .one
    }
    
    @inlinable
    func sqrt() -> FieldElementModel? {
        let candidate = pow(exponentBits: FieldPowModel.squareRootExponentBits)
        guard candidate.square() == self else {
            return nil
        }
        return candidate
    }
    
    var isZero: Bool {
        value.isZero
    }
    
    var isOdd: Bool {
        value.isLeastSignificantBitSet
    }
    
    var data32: Data {
        value.data32
    }
    
    @inlinable
    init(unchecked value: UInt256Model) {
        self.value = value
    }
}

enum FieldPowModel {
    @usableFromInline static let squareRootExponentBits = makeExponentBits(
        from: UInt256Model(
            limbs: [
                0xffffffffbfffff0c,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0x3fffffffffffffff
            ]
        )
    )
    
    @usableFromInline static let legendreExponentBits = makeExponentBits(
        from: UInt256Model(
            limbs: [
                0xffffffff7ffffe17,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0x7fffffffffffffff
            ]
        )
    )
    
    @usableFromInline static let inversionExponentBits = makeExponentBits(
        from: UInt256Model(
            limbs: [
                0xfffffffefffffc2d,
                0xffffffffffffffff,
                0xffffffffffffffff,
                0xffffffffffffffff
            ]
        )
    )
    
    @usableFromInline static func makeExponentBits(from exponent: UInt256Model) -> [Bool] {
        guard let mostSignificantBit = exponent.mostSignificantBitIndex else {
            return [false]
        }
        return stride(from: mostSignificantBit, through: 0, by: -1).map { exponent.testBit(at: $0) }
    }
}

extension FieldElementModel {
    @inlinable
    func invertUsingExponentiation() -> FieldElementModel {
        pow(exponentBits: FieldPowModel.inversionExponentBits)
    }
}
