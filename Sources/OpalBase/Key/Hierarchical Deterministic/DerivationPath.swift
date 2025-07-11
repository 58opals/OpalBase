// DerivationPath.swift

import Foundation

public struct DerivationPath {
    let purpose: Purpose
    let coinType: CoinType
    var account: Account
    let usage: Usage
    let index: UInt32
    
    init(purpose: Purpose = .bip44,
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
    
    public var path: String {
        do {
            return try "m/\(purpose.hardenedIndex.unharden())'/\(coinType.hardenedIndex.unharden())'/\(account.unhardenedIndex.harden())'/\(usage.unhardenedIndex)/\(index)"
        } catch {
            Task {
                await Log.shared.log("The error \(error) occured during unhardening one of the indice of \(purpose.hardenedIndex), \(coinType.hardenedIndex), or \(account.unhardenedIndex).")
            }
            return "‼ PATH without hardening: m/\(purpose.hardenedIndex)/\(coinType.hardenedIndex)/\(account.unhardenedIndex)/\(usage.unhardenedIndex)/\(index)"
        }
    }
}

extension DerivationPath {
    public enum Purpose {
        case bip44
        
        public init?(hardenedIndex: UInt32) {
            switch hardenedIndex {
            case 44:
                self = .bip44
            default:
                return nil
            }
        }
        
        var unhardenedIndex: UInt32 {
            switch self {
            case .bip44:
                return UInt32(44)
            }
        }
        
        var hardenedIndex: UInt32 {
            switch self {
            case .bip44:
                do { return try UInt32(44).harden() }
                catch { fatalError("The index number 44 failed to be hardened.") }
            }
        }
    }
    
    public enum CoinType {
        case bitcoin
        case bitcoinCash
        
        public init?(hardenedIndex: UInt32) {
            switch hardenedIndex {
            case 0:
                self = .bitcoin
            case 145:
                self = .bitcoinCash
            default:
                return nil
            }
        }
        
        var unhardenedIndex: UInt32 {
            switch self {
            case .bitcoin:
                return UInt32(0)
            case .bitcoinCash:
                return UInt32(145)
            }
        }
        
        var hardenedIndex: UInt32 {
            switch self {
            case .bitcoin:
                do { return try UInt32(0).harden() }
                catch { fatalError("The index number 0 failed to be hardened.") }
            case .bitcoinCash:
                do { return try UInt32(145).harden() }
                catch { fatalError("The index number 145 failed to be hardened.") }
            }
        }
    }
    
    public struct Account {
        private(set) var unhardenedIndex: UInt32
        
        public init(rawIndexInteger: UInt32) throws {
            guard rawIndexInteger < 0x80000000 else { throw Error.indexOverflow }
            self.init(unhardenedIndex: rawIndexInteger)
        }
        
        private init(unhardenedIndex: UInt32) {
            self.unhardenedIndex = unhardenedIndex
        }
        
        func getUnhardenedIndex() -> UInt32 {
            return unhardenedIndex
        }
        
        func getHardenedIndex() throws -> UInt32 {
            return try self.unhardenedIndex.harden()
        }
        
        mutating func increase() throws {
            //let currentIndex = unhardenedIndex
            //guard currentIndex < 0x7FFFFFFF else { throw Error.indexOverflow }
            //self.unhardenedIndex = try (currentIndex + 1).harden()
            guard unhardenedIndex < 0x7FFFFFFF else { throw Error.indexOverflow }
            unhardenedIndex += 1
        }
    }
    
    public enum Usage {
        case receiving
        case change
        
        var unhardenedIndex: UInt32 {
            switch self {
            case .receiving:
                0
            case .change:
                1
            }
        }
    }
}

// MARK: -

extension DerivationPath: Hashable {
    public static func == (lhs: DerivationPath, rhs: DerivationPath) -> Bool {
        lhs.path == rhs.path
    }
}
extension DerivationPath: Sendable {}

// MARK: -

extension DerivationPath.Purpose: Hashable {
    public static func == (lhs: DerivationPath.Purpose, rhs: DerivationPath.Purpose) -> Bool {
        lhs.hardenedIndex == rhs.hardenedIndex
    }
}
extension DerivationPath.Purpose: Sendable {}

// MARK: -

extension DerivationPath.CoinType: Hashable {
    public static func == (lhs: DerivationPath.CoinType, rhs: DerivationPath.CoinType) -> Bool {
        lhs.hardenedIndex == rhs.hardenedIndex
    }
}
extension DerivationPath.CoinType: Sendable {}

// MARK: -

extension DerivationPath.Account: Hashable {
    public static func == (lhs: DerivationPath.Account, rhs: DerivationPath.Account) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
    }
}
extension DerivationPath.Account: Sendable {}

// MARK: -

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

// MARK: -

extension DerivationPath: CustomDebugStringConvertible {
    public var debugDescription: String {
        return path
    }
}

extension DerivationPath.Purpose: CustomStringConvertible {
    public var description: String {
        return "\(unhardenedIndex)'"
    }
}

extension DerivationPath.CoinType: CustomStringConvertible {
    public var description: String {
        return "\(unhardenedIndex)'"
    }
}

extension DerivationPath.Account: CustomStringConvertible {
    public var description: String {
        return "\(unhardenedIndex)'"
    }
}

extension DerivationPath.Usage: CustomStringConvertible {
    public var description: String {
        return "\(unhardenedIndex)"
    }
}

// MARK: -

extension DerivationPath.Usage: CaseIterable {}
