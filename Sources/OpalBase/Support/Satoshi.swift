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
        
        let scaledValue = bch * Double(Satoshi.perBCH)
        guard scaledValue.isFinite else { throw Error.exceedsMaximumAmount }
        guard scaledValue >= 0 else { throw Error.negativeResult }
        
        let roundedValue = scaledValue.rounded()
        let roundingError = abs(roundedValue - scaledValue)
        let tolerance = Double.ulpOfOne * roundedValue.magnitude
        guard roundingError <= tolerance else { throw Error.invalidPrecision }
        guard roundedValue <= Double(Satoshi.maximumSatoshi) else { throw Error.exceedsMaximumAmount }
        
        let satoshi = UInt64(roundedValue)
        self.uint64 = satoshi
    }
}

extension Satoshi {
    enum Error: Swift.Error {
        case exceedsMaximumAmount
        case negativeResult
        case invalidPrecision
        case divisionByZero
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
        guard rhs != 0 else { throw Error.divisionByZero }
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

// MARK: - Sequence_+

extension Sequence where Element == Satoshi {
    public func sumSatoshi() throws -> Satoshi {
        try sumSatoshi { $0 }
    }
    
    public func sumSatoshi(or overflowError: @autoclosure () -> Swift.Error) throws -> Satoshi {
        try sumSatoshi(or: overflowError()) { $0 }
    }
}

extension Sequence {
    public func sumSatoshi(_ transform: (Element) throws -> Satoshi) throws -> Satoshi {
        try reduce(Satoshi()) { try $0 + transform($1) }
    }
    
    public func sumSatoshi(or overflowError: @autoclosure () -> Swift.Error,
                    _ transform: (Element) throws -> Satoshi) throws -> Satoshi {
        do {
            return try sumSatoshi(transform)
        } catch let error as Satoshi.Error {
            switch error {
            case .exceedsMaximumAmount:
                throw overflowError()
            default:
                throw error
            }
        } catch {
            throw error
        }
    }
}

extension Sequence where Element: Hashable {
    func deduplicate() -> [Element] {
        var seen = Set<Element>()
        return filter { seen.insert($0).inserted }
    }
}
