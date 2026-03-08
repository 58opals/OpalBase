// OpalBase+DerivationPath+Usage.swift

import Foundation

extension _OpalBase.DerivationPath {
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

extension _OpalBase.DerivationPath.Usage: Hashable {
    public static func == (lhs: OpalBase.DerivationPath.Usage, rhs: OpalBase.DerivationPath.Usage) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
    }
}

extension _OpalBase.DerivationPath.Usage: Sendable {}

extension _OpalBase.DerivationPath.Usage: Codable {
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

extension _OpalBase.DerivationPath.Usage {
    static func resolveTargetUsages(for usage: OpalBase.DerivationPath.Usage?) -> [OpalBase.DerivationPath.Usage] {
        usage.map { [$0] } ?? Self.allCases
    }
}

extension _OpalBase.DerivationPath.Usage: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)" }
}

extension _OpalBase.DerivationPath.Usage: CaseIterable {}
