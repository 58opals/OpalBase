// DerivationPathModel+UsageModel.swift

import Foundation

extension DerivationPathModel {
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

extension DerivationPathModel.UsageModel: Hashable {
    public static func == (lhs: DerivationPathModel.UsageModel, rhs: DerivationPathModel.UsageModel) -> Bool {
        lhs.unhardenedIndex == rhs.unhardenedIndex
    }
}

extension DerivationPathModel.UsageModel: Sendable {}

extension DerivationPathModel.UsageModel: Codable {
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

extension DerivationPathModel.UsageModel {
    static func resolveTargetUsages(for usage: DerivationPathModel.UsageModel?) -> [DerivationPathModel.UsageModel] {
        usage.map { [$0] } ?? Self.allCases
    }
}

extension DerivationPathModel.UsageModel: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)" }
}

extension DerivationPathModel.UsageModel: CaseIterable {}
