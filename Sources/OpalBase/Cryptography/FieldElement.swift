// FieldElement.swift

import Foundation

struct FieldElement: Sendable, Equatable {
    enum Error: Swift.Error, Equatable {
        case invalidFieldValue
        case invalidDataLength(expected: Int, actual: Int)
    }
    
    private let value: UInt256
    
    static let zero = FieldElement(unchecked: UInt256(limbs: [0, 0, 0, 0]))
    static let one = FieldElement(unchecked: UInt256(limbs: [1, 0, 0, 0]))
    static let two = FieldElement(unchecked: UInt256(limbs: [2, 0, 0, 0]))
    static let three = FieldElement(unchecked: UInt256(limbs: [3, 0, 0, 0]))
    static let seven = FieldElement(unchecked: UInt256(limbs: [7, 0, 0, 0]))
    static let eight = FieldElement(unchecked: UInt256(limbs: [8, 0, 0, 0]))
    
    init(value: UInt256) throws {
        guard value.compare(to: Secp256k1.Constant.p) == .orderedAscending else {
            throw Error.invalidFieldValue
        }
        self.value = value
    }
    
    init(data32: Data) throws {
        guard data32.count == 32 else {
            throw Error.invalidDataLength(expected: 32, actual: data32.count)
        }
        let parsed = try UInt256(data32: data32)
        try self.init(value: parsed)
    }
    
    func add(_ other: FieldElement) -> FieldElement {
        let (sum, carry) = value.adding(other.value)
        var reduced = sum
        if carry || reduced.compare(to: Secp256k1.Constant.p) != .orderedAscending {
            reduced = reduced.subtracting(Secp256k1.Constant.p).difference
        }
        return FieldElement(unchecked: reduced)
    }
    
    func sub(_ other: FieldElement) -> FieldElement {
        let (difference, borrow) = value.subtracting(other.value)
        var reduced = difference
        if borrow {
            reduced = reduced.adding(Secp256k1.Constant.p).sum
        }
        return FieldElement(unchecked: reduced)
    }
    
    func negate() -> FieldElement {
        guard !value.isZero else {
            return .zero
        }
        let difference = Secp256k1.Constant.p.subtracting(value).difference
        return FieldElement(unchecked: difference)
    }
    
    func mul(_ other: FieldElement) -> FieldElement {
        let product = value.multipliedFullWidth(by: other.value)
        let reduced = FieldReduction.reduce(product)
        return FieldElement(unchecked: reduced)
    }
    
    func square() -> FieldElement {
        mul(self)
    }
    
    func double() -> FieldElement {
        add(self)
    }
    
    var isQuadraticResidue: Bool {
        pow(exponentBits: FieldPow.legendreExponentBits) == .one
    }
    
    func sqrt() -> FieldElement? {
        let candidate = pow(exponentBits: FieldPow.squareRootExponentBits)
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
    
    init(unchecked value: UInt256) {
        self.value = value
    }
}
