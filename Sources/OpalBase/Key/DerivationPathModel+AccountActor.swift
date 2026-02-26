// DerivationPathModel+AccountActor.swift

import Foundation

extension DerivationPathModel {
    public struct AccountActor {
        public init(rawIndexInteger: UInt32) throws {
            guard rawIndexInteger <= HardenModel.maxUnhardenedValue else { throw Error.indexOverflow }
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
            guard unhardenedIndex < HardenModel.maxUnhardenedValue else { throw Error.indexOverflow }
            unhardenedIndex += 1
        }
    }
}

extension DerivationPathModel.AccountActor: Hashable {
    public static func == (lhs: DerivationPathModel.AccountActor, rhs: DerivationPathModel.AccountActor) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
    }
}

extension DerivationPathModel.AccountActor: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let index = try container.decode(UInt32.self)
        self = try DerivationPathModel.AccountActor(rawIndexInteger: index)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(unhardenedIndex)
    }
}

extension DerivationPathModel.AccountActor: Sendable {}

extension DerivationPathModel.AccountActor: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)'" }
}
