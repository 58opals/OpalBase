// DerivationPath.swift

import Foundation

public struct DerivationPath {
    public let purpose: Purpose
    public let coinType: CoinType
    public var account: Account
    public let usage: Usage
    public let index: UInt32
    
    public init(purpose: Purpose = .bip44,
                coinType: CoinType = .bitcoinCash,
                account: Account,
                usage: Usage,
                index: UInt32) throws {
        self.purpose = purpose
        self.coinType = coinType
        self.account = account
        self.usage = usage
        self.index = index
    }
    
    public func makeIndices() throws -> [UInt32] {
        let accountIndex = try account.deriveHardenedIndex()
        return [
            purpose.hardenedIndex,
            coinType.hardenedIndex,
            accountIndex,
            usage.unhardenedIndex,
            index
        ]
    }
    
    public var path: String {
        "m/\(purpose.unhardenedIndex)'/\(coinType.unhardenedIndex)'/\(account.unhardenedIndex)'/\(usage.unhardenedIndex)/\(index)"
    }
}

extension DerivationPath {
    enum Error: Swift.Error {
        case indexOverflow
        case indexTooLargeForHardening
        case indexTooSmallForUnhardening
    }
}

extension DerivationPath {
    public enum Purpose {
        case bip44
        
        public init?(unhardenedIndex: UInt32) {
            switch unhardenedIndex {
            case 44:
                self = .bip44
            default:
                return nil
            }
        }
        
        public init?(hardenedIndex: UInt32) {
            guard let unhardenedIndex = try? hardenedIndex.unharden() else { return nil }
            self.init(unhardenedIndex: unhardenedIndex)
        }
        
        public var unhardenedIndex: UInt32 {
            switch self {
            case .bip44:
                return UInt32(44)
            }
        }
        
        public var hardenedIndex: UInt32 {
            switch self {
            case .bip44:
                return Harden.harden(44)
            }
        }
    }
    
    public enum CoinType {
        case bitcoin
        case bitcoinCash
        
        public init?(unhardenedIndex: UInt32) {
            switch unhardenedIndex {
            case 0:
                self = .bitcoin
            case 145:
                self = .bitcoinCash
            default:
                return nil
            }
        }
        
        public init?(hardenedIndex: UInt32) {
            guard let unhardenedIndex = try? hardenedIndex.unharden() else { return nil }
            self.init(unhardenedIndex: unhardenedIndex)
        }
        
        public var unhardenedIndex: UInt32 {
            switch self {
            case .bitcoin:
                return UInt32(0)
            case .bitcoinCash:
                return UInt32(145)
            }
        }
        
        public var hardenedIndex: UInt32 {
            switch self {
            case .bitcoin:
                return Harden.harden(0)
            case .bitcoinCash:
                return Harden.harden(145)
            }
        }
    }
    
    public struct Account {
        public init(rawIndexInteger: UInt32) throws {
            guard rawIndexInteger <= Harden.maxUnhardenedValue else { throw Error.indexOverflow }
            self.init(unhardenedIndex: rawIndexInteger)
        }
        
        private init(unhardenedIndex: UInt32) {
            self.unhardenedIndex = unhardenedIndex
        }
        
        public var unhardenedIndex: UInt32
        
        public func deriveHardenedIndex() throws -> UInt32 {
            return try self.unhardenedIndex.harden()
        }
        
        mutating func increase() throws {
            guard unhardenedIndex < Harden.maxUnhardenedValue else { throw Error.indexOverflow }
            unhardenedIndex += 1
        }
    }
    
    public enum Usage {
        case receiving
        case change
        
        public var unhardenedIndex: UInt32 {
            switch self {
            case .receiving:
                0
            case .change:
                1
            }
        }
    }
}

// MARK: - DerivationPath

extension DerivationPath: Hashable {
    public static func == (lhs: DerivationPath, rhs: DerivationPath) -> Bool {
        lhs.path == rhs.path
    }
}
extension DerivationPath: Sendable {}

// MARK: - DerivationPath.Purpose

extension DerivationPath.Purpose: Hashable {
    public static func == (lhs: DerivationPath.Purpose, rhs: DerivationPath.Purpose) -> Bool {
        lhs.hardenedIndex == rhs.hardenedIndex
    }
}

extension DerivationPath.Purpose: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let index = try container.decode(UInt32.self)
        guard let purpose = DerivationPath.Purpose(hardenedIndex: index) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid purpose index") }
        self = purpose
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hardenedIndex)
    }
}

extension DerivationPath.Purpose: Sendable {}

// MARK: - DerivationPath.CoinType

extension DerivationPath.CoinType: Hashable {
    public static func == (lhs: DerivationPath.CoinType, rhs: DerivationPath.CoinType) -> Bool {
        lhs.hardenedIndex == rhs.hardenedIndex
    }
}

extension DerivationPath.CoinType: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let index = try container.decode(UInt32.self)
        guard let coin = DerivationPath.CoinType(hardenedIndex: index) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid coin type index") }
        self = coin
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hardenedIndex)
    }
}

extension DerivationPath.CoinType: Sendable {}

// MARK: - DerivationPath.Account

extension DerivationPath.Account: Hashable {
    public static func == (lhs: DerivationPath.Account, rhs: DerivationPath.Account) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
    }
}

extension DerivationPath.Account: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let index = try container.decode(UInt32.self)
        self = try DerivationPath.Account(rawIndexInteger: index)
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(unhardenedIndex)
    }
}

extension DerivationPath.Account: Sendable {}

// MARK: - DerivationPath.Usage

extension DerivationPath.Usage: Hashable {
    public static func == (lhs: DerivationPath.Usage, rhs: DerivationPath.Usage) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
    }
}
extension DerivationPath.Usage: Sendable {}

extension DerivationPath.Usage: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let value = try container.decode(String.self)
        switch value {
        case "receiving": self = .receiving
        case "change": self = .change
        default: throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid usage value")
        }
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .receiving: try container.encode("receiving")
        case .change: try container.encode("change")
        }
    }
}

extension DerivationPath.Usage {
    static func targets(for usage: DerivationPath.Usage?) -> [DerivationPath.Usage] {
        usage.map { [$0] } ?? Self.allCases
    }
}

// MARK: -

extension DerivationPath: CustomDebugStringConvertible {
    public var debugDescription: String { return path }
}

extension DerivationPath.Purpose: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)'" }
}

extension DerivationPath.CoinType: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)'" }
}

extension DerivationPath.Account: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)'" }
}

extension DerivationPath.Usage: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)" }
}

// MARK: -

extension DerivationPath.Usage: CaseIterable {}
