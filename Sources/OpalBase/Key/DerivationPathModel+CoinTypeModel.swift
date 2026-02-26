// DerivationPathModel+CoinTypeModel.swift

import Foundation

extension DerivationPathModel {
    public enum CoinTypeModel {
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
                return HardenModel.harden(0)
            case .bitcoinCash:
                return HardenModel.harden(145)
            }
        }
    }
}

extension DerivationPathModel.CoinTypeModel: Hashable {
    public static func == (lhs: DerivationPathModel.CoinTypeModel, rhs: DerivationPathModel.CoinTypeModel) -> Bool {
        lhs.hardenedIndex == rhs.hardenedIndex
    }
}

extension DerivationPathModel.CoinTypeModel: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let index = try container.decode(UInt32.self)
        guard let coin = DerivationPathModel.CoinTypeModel(hardenedIndex: index) else { throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid coin type index") }
        self = coin
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hardenedIndex)
    }
}

extension DerivationPathModel.CoinTypeModel: Sendable {}

extension DerivationPathModel.CoinTypeModel: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)'" }
}
