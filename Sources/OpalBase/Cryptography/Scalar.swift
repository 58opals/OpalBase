// Scalar.swift

import Foundation

struct Scalar: Sendable, Equatable {
    enum Error: Swift.Error, Equatable {
        case invalidDataLength(expected: Int, actual: Int)
        case invalidScalarValue
        case zeroNotAllowed
    }
    
    @usableFromInline let value: UInt256
    
    static let zero = Scalar(unchecked: UInt256(limbs: [0, 0, 0, 0]))
    static let one = Scalar(unchecked: UInt256(limbs: [1, 0, 0, 0]))
    
    init(data32: Data, requireNonZero: Bool = false) throws {
        guard data32.count == 32 else {
            throw Error.invalidDataLength(expected: 32, actual: data32.count)
        }
        let parsed = try UInt256(data32: data32)
        guard parsed.compare(to: Secp256k1.Constant.n) == .orderedAscending else {
            throw Error.invalidScalarValue
        }
        guard !requireNonZero || !parsed.isZero else {
            throw Error.zeroNotAllowed
        }
        value = parsed
    }
    
    init(value: UInt256) throws {
        guard value.compare(to: Secp256k1.Constant.n) == .orderedAscending else {
            throw Error.invalidScalarValue
        }
        self.value = value
    }
    
    func addModN(_ other: Scalar) -> Scalar {
        let (sum, carry) = value.adding(other.value)
        var reduced = sum
        if carry || reduced.compare(to: Secp256k1.Constant.n) != .orderedAscending {
            reduced = reduced.subtracting(Secp256k1.Constant.n).difference
        }
        return Scalar(unchecked: reduced)
    }
    
    func subModN(_ other: Scalar) -> Scalar {
        let (difference, borrow) = value.subtracting(other.value)
        var reduced = difference
        if borrow {
            reduced = reduced.adding(Secp256k1.Constant.n).sum
        }
        return Scalar(unchecked: reduced)
    }
    
    func mulModN(_ other: Scalar) -> Scalar {
        let product = value.multipliedFullWidth(by: other.value)
        let reduced = ScalarReduction.reduce(product)
        return Scalar(unchecked: reduced)
    }
    
    func negateModN() -> Scalar {
        guard !value.isZero else {
            return .zero
        }
        let difference = Secp256k1.Constant.n.subtracting(value).difference
        return Scalar(unchecked: difference)
    }
    
    var isZero: Bool {
        value.isZero
    }
    
    @inlinable
    func bit(at index: Int) -> Bool {
        value.bit(at: index)
    }
    
    var data32: Data {
        value.data32
    }
    
    @inlinable
    init(unchecked value: UInt256) {
        self.value = value
    }
}

extension Scalar {
    func compare(to other: Scalar) -> ComparisonResult {
        value.compare(to: other.value)
    }
    
    @usableFromInline
    var limbs: InlineArray<4, UInt64> {
        value.limbs
    }
    
    func forEachBigEndianByte(_ body: (UInt8) -> Void) {
        for limbIndex in stride(from: 3, through: 0, by: -1) {
            var limb = value.limbs[limbIndex].bigEndian
            withUnsafeBytes(of: &limb) { bytes in
                for byte in bytes {
                    body(byte)
                }
            }
        }
    }
    
    func invert() throws -> Scalar {
        guard !isZero else {
            throw Scalar.Error.zeroNotAllowed
        }
        return pow(exponentBits: ScalarPow.inversionExponentBits)
    }
}
