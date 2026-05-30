// OpalBase+Key+DerivationPath+Purpose.swift

import Foundation

extension _OpalBase.Key.DerivationPath {
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
                return HardenedIndex.harden(44)
            }
        }
    }
}

extension _OpalBase.Key.DerivationPath.Purpose: Hashable {
    public static func == (lhs: OpalBase.Key.DerivationPath.Purpose, rhs: OpalBase.Key.DerivationPath.Purpose) -> Bool {
        lhs.hardenedIndex == rhs.hardenedIndex
    }
}

extension _OpalBase.Key.DerivationPath.Purpose: Codable {
    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let index = try container.decode(UInt32.self)
        guard let purpose = OpalBase.Key.DerivationPath.Purpose(hardenedIndex: index) else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Invalid purpose index")
        }
        self = purpose
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(hardenedIndex)
    }
}

extension _OpalBase.Key.DerivationPath.Purpose: Sendable {}

extension _OpalBase.Key.DerivationPath.Purpose: CustomStringConvertible {
    public var description: String { return "\(unhardenedIndex)'" }
}
