// OpalBase.DerivationPath+UsageModel.swift

import Foundation

extension _OpalBase.DerivationPath {
    public enum UsageModel {
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

extension _OpalBase.DerivationPath.UsageModel: Hashable {
    public static func == (lhs: OpalBase.DerivationPath.UsageModel, rhs: OpalBase.DerivationPath.UsageModel) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
    }
}

extension _OpalBase.DerivationPath.UsageModel: Sendable {}

extension _OpalBase.DerivationPath.UsageModel: Codable {
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

extension _OpalBase.DerivationPath.UsageModel {
    static func resolveTargetUsages(for usage: OpalBase.DerivationPath.UsageModel?) -> [OpalBase.DerivationPath.UsageModel] {
        usage.map { [$0] } ?? Self.allCases
    }
}

extension _OpalBase.DerivationPath.UsageModel: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)" }
}

extension _OpalBase.DerivationPath.UsageModel: CaseIterable {}
