import Foundation

struct Satoshi {
    var value: UInt64
    
    static let perBCH: UInt64 = 100_000_000
    static let maximumBCH: UInt64 = 21_000_000
    static let maximumSatoshi: UInt64 = Satoshi.maximumBCH * Satoshi.perBCH
    
    init(_ value: UInt64) throws {
        guard value <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        self.value = value
    }
    
    init(bch: Double) throws {
        let satoshi = UInt64(bch * Double(Satoshi.perBCH))
        guard satoshi <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        self.value = satoshi
    }
    
    var bch: Decimal {
        return Decimal(value) / Decimal(Satoshi.perBCH)
    }
}

extension Satoshi: Equatable, Comparable {
    static func + (lhs: Satoshi, rhs: Satoshi) throws -> Satoshi {
        let result = lhs.value + rhs.value
        guard result <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try Satoshi(result)
    }
    
    static func - (lhs: Satoshi, rhs: Satoshi) throws -> Satoshi {
        guard lhs.value >= rhs.value else { throw Error.negativeResult }
        return try Satoshi(lhs.value - rhs.value)
    }
    
    static func * (lhs: Satoshi, rhs: UInt64) throws -> Satoshi {
        let result = lhs.value * rhs
        guard result <= Satoshi.maximumSatoshi else { throw Error.exceedsMaximumAmount }
        return try Satoshi(result)
    }
    
    static func / (lhs: Satoshi, rhs: UInt64) throws -> Satoshi {
        return try Satoshi(lhs.value / rhs)
    }
    
    static func < (lhs: Satoshi, rhs: Satoshi) -> Bool {
        return lhs.value < rhs.value
    }
    
    static func <= (lhs: Satoshi, rhs: Satoshi) -> Bool {
        return lhs.value <= rhs.value
    }
    
    static func > (lhs: Satoshi, rhs: Satoshi) -> Bool {
        return lhs.value > rhs.value
    }
    
    static func >= (lhs: Satoshi, rhs: Satoshi) -> Bool {
        return lhs.value >= rhs.value
    }
}

extension Satoshi {
    enum Error: Swift.Error {
        case exceedsMaximumAmount
        case negativeResult
    }
}

extension Satoshi: CustomStringConvertible {
    var description: String {
        return "\(value) satoshi"
    }
}
