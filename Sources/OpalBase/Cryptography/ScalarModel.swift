// ScalarModel.swift

import Foundation

struct ScalarModel: Sendable, Equatable {
    enum Error: Swift.Error, Equatable {
        case invalidDataLength(expected: Int, actual: Int)
        case invalidScalarValue
        case zeroNotAllowed
    }
    
    @usableFromInline let value: UInt256Model
    
    static let zero = ScalarModel(unchecked: UInt256Model(limbs: [0, 0, 0, 0]))
    static let one = ScalarModel(unchecked: UInt256Model(limbs: [1, 0, 0, 0]))
    
    init(data32: Data, requireNonZero: Bool = false) throws {
        guard data32.count == 32 else {
            throw Error.invalidDataLength(expected: 32, actual: data32.count)
        }
        let parsed = try UInt256Model(data32: data32)
        guard parsed.compare(to: Secp256k1Model.Constant.n) == .orderedAscending else {
            throw Error.invalidScalarValue
        }
        guard !requireNonZero || !parsed.isZero else {
            throw Error.zeroNotAllowed
        }
        value = parsed
    }
    
    init(value: UInt256Model) throws {
        guard value.compare(to: Secp256k1Model.Constant.n) == .orderedAscending else {
            throw Error.invalidScalarValue
        }
        self.value = value
    }
    
    func addModN(_ other: ScalarModel) -> ScalarModel {
        let (sum, carry) = value.add(other.value)
        var reduced = sum
        if carry || reduced.compare(to: Secp256k1Model.Constant.n) != .orderedAscending {
            reduced = reduced.subtract(Secp256k1Model.Constant.n).difference
        }
        return ScalarModel(unchecked: reduced)
    }
    
    func subModN(_ other: ScalarModel) -> ScalarModel {
        let (difference, borrow) = value.subtract(other.value)
        var reduced = difference
        if borrow {
            reduced = reduced.add(Secp256k1Model.Constant.n).sum
        }
        return ScalarModel(unchecked: reduced)
    }
    
    func mulModN(_ other: ScalarModel) -> ScalarModel {
        let product = value.multiplyFullWidth(by: other.value)
        let reduced = ScalarReductionModel.reduce(product)
        return ScalarModel(unchecked: reduced)
    }
    
    func negateModN() -> ScalarModel {
        guard !value.isZero else {
            return .zero
        }
        let difference = Secp256k1Model.Constant.n.subtract(value).difference
        return ScalarModel(unchecked: difference)
    }
    
    var isZero: Bool {
        value.isZero
    }
    
    @inlinable
    func testBit(at index: Int) -> Bool {
        value.testBit(at: index)
    }
    
    var data32: Data {
        value.data32
    }
    
    @inlinable
    init(unchecked value: UInt256Model) {
        self.value = value
    }
}

enum ScalarPowModel {
    static let inversionExponentBits = makeExponentBits(
        from: UInt256Model(
            limbs: [
                0xbfd25e8cd036413f,
                0xbaaedce6af48a03b,
                0xfffffffffffffffe,
                0xffffffffffffffff
            ]
        )
    )
    
    private static func makeExponentBits(from exponent: UInt256Model) -> [Bool] {
        guard let mostSignificantBit = exponent.mostSignificantBitIndex else {
            return [false]
        }
        return stride(from: mostSignificantBit, through: 0, by: -1).map { exponent.testBit(at: $0) }
    }
}

extension ScalarModel {
    func compare(to other: ScalarModel) -> ComparisonResult {
        value.compare(to: other.value)
    }
    
    @usableFromInline
    var limbs: InlineArray<4, UInt64> {
        value.limbs
    }
    
    func iterateBigEndianBytes(_ body: (UInt8) -> Void) {
        for limbIndex in stride(from: 3, through: 0, by: -1) {
            var limb = value.limbs[limbIndex].bigEndian
            withUnsafeBytes(of: &limb) { bytes in
                for byte in bytes {
                    body(byte)
                }
            }
        }
    }
    
    func invert() throws -> ScalarModel {
        guard !isZero else {
            throw ScalarModel.Error.zeroNotAllowed
        }
        return pow(exponentBits: ScalarPowModel.inversionExponentBits)
    }
}
