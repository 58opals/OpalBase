// OpalBase+Satoshi.swift

import Foundation

extension OpalBase {
    public struct Satoshi {
        public var uint64: UInt64
        public var bch: Decimal { Decimal(uint64) / Decimal(OpalBase.Satoshi.perBCH) }
        
        static let perBCH: UInt64 = 100_000_000
        static let maximumBCH: UInt64 = 21_000_000
        static let maximumSatoshi: UInt64 = OpalBase.Satoshi.maximumBCH * OpalBase.Satoshi.perBCH
        
        public init() {
            self.uint64 = 0
        }
        
        public init(_ value: UInt64) throws {
            guard value <= OpalBase.Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
            self.uint64 = value
        }
        
        public init(bch: Double) throws {
            guard bch.isFinite else { throw Error.exceedsMaximumAmount }
            guard bch >= 0 else { throw Error.negativeResult }
            
            let scaledValue = bch * Double(OpalBase.Satoshi.perBCH)
            guard scaledValue.isFinite else { throw Error.exceedsMaximumAmount }
            guard scaledValue >= 0 else { throw Error.negativeResult }
            
            let roundedValue = scaledValue.rounded()
            let roundingError = abs(roundedValue - scaledValue)
            let tolerance = Double.ulpOfOne * roundedValue.magnitude
            guard roundingError <= tolerance else { throw Error.invalidPrecision }
            guard roundedValue <= Double(OpalBase.Satoshi.maximumSatoshi) else { throw Error.exceedsMaximumAmount }
            
            let satoshi = UInt64(roundedValue)
            self.uint64 = satoshi
        }
    }
}

extension _OpalBase.Satoshi: CustomStringConvertible {
    public var description: String {
        "BCH: \(bch.description) | OpalBase.Satoshi: \(uint64.description)"
    }
}

extension _OpalBase.Satoshi: Hashable {
    public static func + (lhs: OpalBase.Satoshi, rhs: OpalBase.Satoshi) throws -> OpalBase.Satoshi {
        let (sum, didOverflow) = lhs.uint64.addingReportingOverflow(rhs.uint64)
        guard didOverflow == false else { throw Error.exceedsMaximumAmount }
        guard sum <= OpalBase.Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try OpalBase.Satoshi(sum)
    }
    
    public static func - (lhs: OpalBase.Satoshi, rhs: OpalBase.Satoshi) throws -> OpalBase.Satoshi {
        guard lhs.uint64 >= rhs.uint64 else { throw Error.negativeResult }
        return try OpalBase.Satoshi(lhs.uint64 - rhs.uint64)
    }
    
    public static func * (lhs: OpalBase.Satoshi, rhs: UInt64) throws -> OpalBase.Satoshi {
        let (multiplication, didOverflow) = lhs.uint64.multipliedReportingOverflow(by: rhs)
        guard didOverflow == false else { throw Error.exceedsMaximumAmount }
        guard multiplication <= OpalBase.Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try OpalBase.Satoshi(multiplication)
    }
    
    public static func / (lhs: OpalBase.Satoshi, rhs: UInt64) throws -> OpalBase.Satoshi {
        guard rhs != 0 else { throw Error.divisionByZero }
        return try OpalBase.Satoshi(lhs.uint64 / rhs)
    }
    
    public static func < (lhs: OpalBase.Satoshi, rhs: OpalBase.Satoshi) -> Bool {
        lhs.uint64 < rhs.uint64
    }
    
    public static func <= (lhs: OpalBase.Satoshi, rhs: OpalBase.Satoshi) -> Bool {
        lhs.uint64 <= rhs.uint64
    }
    
    public static func > (lhs: OpalBase.Satoshi, rhs: OpalBase.Satoshi) -> Bool {
        lhs.uint64 > rhs.uint64
    }
    
    public static func >= (lhs: OpalBase.Satoshi, rhs: OpalBase.Satoshi) -> Bool {
        lhs.uint64 >= rhs.uint64
    }
}

extension _OpalBase.Satoshi: Sendable {}

// MARK: - Sequence_+

extension Sequence where Element == OpalBase.Satoshi {
    public func sumSatoshi() throws -> OpalBase.Satoshi {
        try sumSatoshi { $0 }
    }
    
    public func sumSatoshi(or overflowError: @autoclosure () -> Swift.Error) throws -> OpalBase.Satoshi {
        try sumSatoshi(or: overflowError()) { $0 }
    }
}

extension Sequence {
    public func sumSatoshi(_ transform: (Element) throws -> OpalBase.Satoshi) throws -> OpalBase.Satoshi {
        try reduce(OpalBase.Satoshi()) { try $0 + transform($1) }
    }
    
    public func sumSatoshi(or overflowError: @autoclosure () -> Swift.Error,
                           _ transform: (Element) throws -> OpalBase.Satoshi) throws -> OpalBase.Satoshi {
        do {
            return try sumSatoshi(transform)
        } catch let error as OpalBase.Satoshi.Error {
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
