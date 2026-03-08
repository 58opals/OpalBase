// FieldElement52Model.swift

import Foundation

struct FieldElement52Model: Sendable, Equatable {
    @usableFromInline var limbs: InlineArray<5, UInt64>
    
    @usableFromInline static let zero = FieldElement52Model(fromUInt256: .zero)
    @usableFromInline static let one = FieldElement52Model(fromUInt256: .one)
    @usableFromInline static let two = FieldElement52Model(fromUInt256: UInt256Model(limbs: [2, 0, 0, 0]))
    @usableFromInline static let three = FieldElement52Model(fromUInt256: UInt256Model(limbs: [3, 0, 0, 0]))
    @usableFromInline static let seven = FieldElement52Model(fromUInt256: UInt256Model(limbs: [7, 0, 0, 0]))
    @usableFromInline static let eight = FieldElement52Model(fromUInt256: UInt256Model(limbs: [8, 0, 0, 0]))
    
    @inlinable
    init(fromUInt256 value: UInt256Model) {
        var reduced = value
        if reduced.compare(to: OpalBase.Cryptography.Secp256k1.Constant.p) != .orderedAscending {
            reduced = reduced.subtract(OpalBase.Cryptography.Secp256k1.Constant.p).difference
        }
        limbs = FieldElement52Model.makeLimbs(from: reduced)
    }
    
    @inlinable
    var asUInt256: UInt256Model {
        FieldElement52Model.makeUInt256(from: limbs)
    }
    
    @inlinable
    var data32: Data {
        asUInt256.data32
    }
    
    @inlinable
    func add(_ other: FieldElement52Model) -> FieldElement52Model {
        let (sum, carry) = asUInt256.add(other.asUInt256)
        var reduced = sum
        if carry || reduced.compare(to: OpalBase.Cryptography.Secp256k1.Constant.p) != .orderedAscending {
            reduced = reduced.subtract(OpalBase.Cryptography.Secp256k1.Constant.p).difference
        }
        return FieldElement52Model(fromUInt256: reduced)
    }
    
    @inlinable
    func sub(_ other: FieldElement52Model) -> FieldElement52Model {
        let (difference, borrow) = asUInt256.subtract(other.asUInt256)
        var reduced = difference
        if borrow {
            reduced = reduced.add(OpalBase.Cryptography.Secp256k1.Constant.p).sum
        }
        return FieldElement52Model(fromUInt256: reduced)
    }
    
    @inlinable
    func negate() -> FieldElement52Model {
        guard !asUInt256.isZero else {
            return .zero
        }
        let difference = OpalBase.Cryptography.Secp256k1.Constant.p.subtract(asUInt256).difference
        return FieldElement52Model(fromUInt256: difference)
    }
    
    @inlinable
    func mul(_ other: FieldElement52Model) -> FieldElement52Model {
        let product = asUInt256.multiplyFullWidth(by: other.asUInt256)
        let reduced = FieldReductionModel.reduce(product)
        return FieldElement52Model(fromUInt256: reduced)
    }
    
    @inlinable
    func square() -> FieldElement52Model {
        let product = asUInt256.squareFullWidth()
        let reduced = FieldReductionModel.reduce(product)
        return FieldElement52Model(fromUInt256: reduced)
    }
    
    @inlinable
    func double() -> FieldElement52Model {
        add(self)
    }
    
    @inlinable
    func normalize() -> FieldElement52Model {
        var reduced = asUInt256
        if reduced.compare(to: OpalBase.Cryptography.Secp256k1.Constant.p) != .orderedAscending {
            reduced = reduced.subtract(OpalBase.Cryptography.Secp256k1.Constant.p).difference
        }
        return FieldElement52Model(fromUInt256: reduced)
    }
    
    @inlinable
    func invert() -> FieldElement52Model {
        let element = FieldElementModel(unchecked: asUInt256)
        let inverted = element.invert()
        return FieldElement52Model(fromUInt256: inverted.value)
    }
    
    @inlinable
    var isZero: Bool {
        asUInt256.isZero
    }
    
    @inlinable
    var isOdd: Bool {
        asUInt256.isLeastSignificantBitSet
    }
    
    @inlinable
    static func == (lhs: FieldElement52Model, rhs: FieldElement52Model) -> Bool {
        lhs.limbs[0] == rhs.limbs[0]
        && lhs.limbs[1] == rhs.limbs[1]
        && lhs.limbs[2] == rhs.limbs[2]
        && lhs.limbs[3] == rhs.limbs[3]
        && lhs.limbs[4] == rhs.limbs[4]
    }
    
    @usableFromInline
    static func makeLimbs(from value: UInt256Model) -> InlineArray<5, UInt64> {
        let limbMask: UInt64 = 0x000f_ffff_ffff_ffff
        let lowerMask40: UInt64 = 0x0000_00ff_ffff_ffff
        let lowerMask28: UInt64 = 0x0000_0000_0fff_ffff
        let lowerMask16: UInt64 = 0x0000_0000_0000_ffff
        let limbZero = value.limbs[0] & limbMask
        let limbOne = ((value.limbs[0] >> 52) | ((value.limbs[1] & lowerMask40) << 12)) & limbMask
        let limbTwo = ((value.limbs[1] >> 40) | ((value.limbs[2] & lowerMask28) << 24)) & limbMask
        let limbThree = ((value.limbs[2] >> 28) | ((value.limbs[3] & lowerMask16) << 36)) & limbMask
        let limbFour = (value.limbs[3] >> 16) & limbMask
        return [limbZero, limbOne, limbTwo, limbThree, limbFour]
    }
    
    @usableFromInline
    static func makeUInt256(from limbs: InlineArray<5, UInt64>) -> UInt256Model {
        let limbMask: UInt64 = 0x000f_ffff_ffff_ffff
        let lowerMask12: UInt64 = 0x0000_0000_0000_0fff
        let lowerMask24: UInt64 = 0x0000_0000_00ff_ffff
        let lowerMask36: UInt64 = 0x0000_000f_ffff_ffff
        let lowerMask48: UInt64 = 0x0000_ffff_ffff_ffff
        let limbZero = limbs[0] & limbMask
        let limbOne = limbs[1] & limbMask
        let limbTwo = limbs[2] & limbMask
        let limbThree = limbs[3] & limbMask
        let limbFour = limbs[4] & limbMask
        let wordZero = limbZero | ((limbOne & lowerMask12) << 52)
        let wordOne = (limbOne >> 12) | ((limbTwo & lowerMask24) << 40)
        let wordTwo = (limbTwo >> 24) | ((limbThree & lowerMask36) << 28)
        let wordThree = (limbThree >> 36) | ((limbFour & lowerMask48) << 16)
        return UInt256Model(limbs: [wordZero, wordOne, wordTwo, wordThree])
    }
}
