// OpalBase+Satoshi.swift

import Foundation

extension OpalBase {
    public struct Satoshi {
        public private(set) var uint64: UInt64
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

            guard let decimalValue = Decimal(string: String(describing: bch)) else {
                throw Error.invalidPrecision
            }
            var scaledValue = decimalValue * Decimal(OpalBase.Satoshi.perBCH)
            guard scaledValue <= Decimal(OpalBase.Satoshi.maximumSatoshi) else {
                throw Error.exceedsMaximumAmount
            }

            var roundedValue = Decimal()
            NSDecimalRound(&roundedValue, &scaledValue, 0, .plain)
            guard scaledValue == roundedValue else { throw Error.invalidPrecision }

            let satoshiNumber = NSDecimalNumber(decimal: roundedValue)
            self.uint64 = satoshiNumber.uint64Value
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

extension _OpalBase.Satoshi {
    public static func sum<S: Sequence>(_ values: S) throws -> OpalBase.Satoshi where S.Element == OpalBase.Satoshi {
        try sum(of: values) { $0 }
    }

    public static func sum<S: Sequence>(
        _ values: S,
        or overflowError: @autoclosure () -> Swift.Error
    ) throws -> OpalBase.Satoshi where S.Element == OpalBase.Satoshi {
        try sum(of: values, or: overflowError()) { $0 }
    }

    public static func sum<S: Sequence>(
        of values: S,
        _ transform: (S.Element) throws -> OpalBase.Satoshi
    ) throws -> OpalBase.Satoshi {
        try values.reduce(OpalBase.Satoshi()) { try $0 + transform($1) }
    }

    public static func sum<S: Sequence>(
        of values: S,
        or overflowError: @autoclosure () -> Swift.Error,
        _ transform: (S.Element) throws -> OpalBase.Satoshi
    ) throws -> OpalBase.Satoshi {
        do {
            return try sum(of: values, transform)
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

// MARK: - Sequence_+

extension Sequence where Element == OpalBase.Satoshi {
    func sumSatoshi() throws -> OpalBase.Satoshi {
        try sumSatoshi { $0 }
    }
    
    func sumSatoshi(or overflowError: @autoclosure () -> Swift.Error) throws -> OpalBase.Satoshi {
        try sumSatoshi(or: overflowError()) { $0 }
    }
}

extension Sequence {
    func sumSatoshi(_ transform: (Element) throws -> OpalBase.Satoshi) throws -> OpalBase.Satoshi {
        try reduce(OpalBase.Satoshi()) { try $0 + transform($1) }
    }
    
    func sumSatoshi(or overflowError: @autoclosure () -> Swift.Error,
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
