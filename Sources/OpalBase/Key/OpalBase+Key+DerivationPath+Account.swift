// OpalBase+Key+DerivationPath+Account.swift

import Foundation

extension _OpalBase.Key.DerivationPath {
    public struct Account {
        public init(rawIndexInteger: UInt32) throws {
            guard rawIndexInteger <= Harden.maxUnhardenedValue else { throw Error.indexOverflow }
            self.init(unhardenedIndex: rawIndexInteger)
        }

        private init(unhardenedIndex: UInt32) {
            self.unhardenedIndex = unhardenedIndex
        }

        public var unhardenedIndex: UInt32

        public func deriveHardenedIndex() throws -> UInt32 { try unhardenedIndex.harden() }

        mutating func increase() throws {
            guard unhardenedIndex < Harden.maxUnhardenedValue else { throw Error.indexOverflow }
            unhardenedIndex += 1
        }
    }
}

extension _OpalBase.Key.DerivationPath.Account: Hashable {
    public static func == (lhs: OpalBase.Key.DerivationPath.Account, rhs: OpalBase.Key.DerivationPath.Account) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
    }
}

extension _OpalBase.Key.DerivationPath.Account: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let index = try container.decode(UInt32.self)
        self = try OpalBase.Key.DerivationPath.Account(rawIndexInteger: index)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(unhardenedIndex)
    }
}

extension _OpalBase.Key.DerivationPath.Account: Sendable {}

extension _OpalBase.Key.DerivationPath.Account: CustomStringConvertible {
    public var description: String { "\(unhardenedIndex)'" }
}
