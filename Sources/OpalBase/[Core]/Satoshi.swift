// Satoshi.swift

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
        guard bch.isFinite else { throw Error.exceedsMaximumAmount }
        guard bch >= 0 else { throw Error.negativeResult }
        
        let scaledValue = (bch * Double(Satoshi.perBCH)).rounded()
        guard scaledValue.isFinite else { throw Error.exceedsMaximumAmount }
        guard scaledValue >= 0 else { throw Error.negativeResult }
        guard scaledValue <= Double(Satoshi.maximumSatoshi) else { throw Error.exceedsMaximumAmount }
        
        let satoshi = UInt64(scaledValue)
        self.uint64 = satoshi
    }
}

extension Satoshi {
    enum Error: Swift.Error {
        case exceedsMaximumAmount
        case negativeResult
        case invalidPrecision
    }
}

extension Satoshi: CustomStringConvertible {
    public var description: String {
        return "BCH: \(bch.description) | Satoshi: \(uint64.description)"
    }
}

extension Satoshi: Hashable {
    public static func + (lhs: Satoshi, rhs: Satoshi) throws -> Satoshi {
        let (sum, didOverflow) = lhs.uint64.addingReportingOverflow(rhs.uint64)
        guard didOverflow == false else { throw Error.exceedsMaximumAmount }
        guard sum <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try Satoshi(sum)
    }
    
    public static func - (lhs: Satoshi, rhs: Satoshi) throws -> Satoshi {
        guard lhs.uint64 >= rhs.uint64 else { throw Error.negativeResult }
        return try Satoshi(lhs.uint64 - rhs.uint64)
    }
    
    public static func * (lhs: Satoshi, rhs: UInt64) throws -> Satoshi {
        let (multiplication, didOverflow) = lhs.uint64.multipliedReportingOverflow(by: rhs)
        guard didOverflow == false else { throw Error.exceedsMaximumAmount }
        guard multiplication <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try Satoshi(multiplication)
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

extension Satoshi: Sendable {}
