import Foundation

public struct Satoshi {
    public var uint64: UInt64
    public var bch: Decimal { return Decimal(uint64) / Decimal(Satoshi.perBCH) }
    
    static let perBCH: UInt64 = 100_000_000
    static let maximumBCH: UInt64 = 21_000_000
    static let maximumSatoshi: UInt64 = Satoshi.maximumBCH * Satoshi.perBCH
    
    public init() {
        self.uint64 = 0
    }
    
    public init(_ value: UInt64) throws {
        guard value <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        self.uint64 = value
    }
    
    public init(bch: Double) throws {
        let satoshi = UInt64(bch * Double(Satoshi.perBCH))
        guard satoshi <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        self.uint64 = satoshi
    }
}

extension Satoshi: Hashable {
    public static func + (lhs: Satoshi, rhs: Satoshi) throws -> Satoshi {
        let result = lhs.uint64 + rhs.uint64
        guard result <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try Satoshi(result)
    }
    
    public static func - (lhs: Satoshi, rhs: Satoshi) throws -> Satoshi {
        guard lhs.uint64 >= rhs.uint64 else { throw Error.negativeResult }
        return try Satoshi(lhs.uint64 - rhs.uint64)
    }
    
    public static func * (lhs: Satoshi, rhs: UInt64) throws -> Satoshi {
        let result = lhs.uint64 * rhs
        guard result <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try Satoshi(result)
    }
    
    public static func / (lhs: Satoshi, rhs: UInt64) throws -> Satoshi {
        return try Satoshi(lhs.uint64 / rhs)
    }
    
    public static func < (lhs: Satoshi, rhs: Satoshi) -> Bool {
        return lhs.uint64 < rhs.uint64
    }
    
    public static func <= (lhs: Satoshi, rhs: Satoshi) -> Bool {
        return lhs.uint64 <= rhs.uint64
    }
    
    public static func > (lhs: Satoshi, rhs: Satoshi) -> Bool {
        return lhs.uint64 > rhs.uint64
    }
    
    public static func >= (lhs: Satoshi, rhs: Satoshi) -> Bool {
        return lhs.uint64 >= rhs.uint64
    }
}

extension Satoshi: CustomStringConvertible {
    public var description: String {
        return "BCH: \(bch.description) | Satoshi: \(uint64.description)"
    }
}
