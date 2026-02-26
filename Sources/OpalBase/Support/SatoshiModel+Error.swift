// SatoshiModel.swift

import Foundation

public struct SatoshiModel {
    public var uint64: UInt64
    public var bch: Decimal { return Decimal(uint64) / Decimal(SatoshiModel.perBCH) }
    
    static let perBCH: UInt64 = 100_000_000
    static let maximumBCH: UInt64 = 21_000_000
    static let maximumSatoshi: UInt64 = SatoshiModel.maximumBCH * SatoshiModel.perBCH
    
    public init() {
        self.uint64 = 0
    }
    
    public init(_ value: UInt64) throws {
        guard value <= SatoshiModel.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        self.uint64 = value
    }
    
    public init(bch: Double) throws {
        guard bch.isFinite else { throw Error.exceedsMaximumAmount }
        guard bch >= 0 else { throw Error.negativeResult }
        
        let scaledValue = bch * Double(SatoshiModel.perBCH)
        guard scaledValue.isFinite else { throw Error.exceedsMaximumAmount }
        guard scaledValue >= 0 else { throw Error.negativeResult }
        
        let roundedValue = scaledValue.rounded()
        let roundingError = abs(roundedValue - scaledValue)
        let tolerance = Double.ulpOfOne * roundedValue.magnitude
        guard roundingError <= tolerance else { throw Error.invalidPrecision }
        guard roundedValue <= Double(SatoshiModel.maximumSatoshi) else { throw Error.exceedsMaximumAmount }
        
        let satoshi = UInt64(roundedValue)
        self.uint64 = satoshi
    }
}

extension SatoshiModel {
    enum Error: Swift.Error {
        case exceedsMaximumAmount
        case negativeResult
        case invalidPrecision
        case divisionByZero
    }
}

extension SatoshiModel: CustomStringConvertible {
    public var description: String {
        return "BCH: \(bch.description) | SatoshiModel: \(uint64.description)"
    }
}

extension SatoshiModel: Hashable {
    public static func + (lhs: SatoshiModel, rhs: SatoshiModel) throws -> SatoshiModel {
        let (sum, didOverflow) = lhs.uint64.addingReportingOverflow(rhs.uint64)
        guard didOverflow == false else { throw Error.exceedsMaximumAmount }
        guard sum <= SatoshiModel.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try SatoshiModel(sum)
    }
    
    public static func - (lhs: SatoshiModel, rhs: SatoshiModel) throws -> SatoshiModel {
        guard lhs.uint64 >= rhs.uint64 else { throw Error.negativeResult }
        return try SatoshiModel(lhs.uint64 - rhs.uint64)
    }
    
    public static func * (lhs: SatoshiModel, rhs: UInt64) throws -> SatoshiModel {
        let (multiplication, didOverflow) = lhs.uint64.multipliedReportingOverflow(by: rhs)
        guard didOverflow == false else { throw Error.exceedsMaximumAmount }
        guard multiplication <= SatoshiModel.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try SatoshiModel(multiplication)
    }
    
    public static func / (lhs: SatoshiModel, rhs: UInt64) throws -> SatoshiModel {
        guard rhs != 0 else { throw Error.divisionByZero }
        return try SatoshiModel(lhs.uint64 / rhs)
    }
    
    public static func < (lhs: SatoshiModel, rhs: SatoshiModel) -> Bool {
        return lhs.uint64 < rhs.uint64
    }
    
    public static func <= (lhs: SatoshiModel, rhs: SatoshiModel) -> Bool {
        return lhs.uint64 <= rhs.uint64
    }
    
    public static func > (lhs: SatoshiModel, rhs: SatoshiModel) -> Bool {
        return lhs.uint64 > rhs.uint64
    }
    
    public static func >= (lhs: SatoshiModel, rhs: SatoshiModel) -> Bool {
        return lhs.uint64 >= rhs.uint64
    }
}

extension SatoshiModel: Sendable {}

// MARK: - Sequence_+

extension Sequence where Element == SatoshiModel {
    public func sumSatoshi() throws -> SatoshiModel {
        try sumSatoshi { $0 }
    }
    
    public func sumSatoshi(or overflowError: @autoclosure () -> Swift.Error) throws -> SatoshiModel {
        try sumSatoshi(or: overflowError()) { $0 }
    }
}

extension Sequence {
    public func sumSatoshi(_ transform: (Element) throws -> SatoshiModel) throws -> SatoshiModel {
        try reduce(SatoshiModel()) { try $0 + transform($1) }
    }
    
    public func sumSatoshi(or overflowError: @autoclosure () -> Swift.Error,
                    _ transform: (Element) throws -> SatoshiModel) throws -> SatoshiModel {
        do {
            return try sumSatoshi(transform)
        } catch let error as SatoshiModel.Error {
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
