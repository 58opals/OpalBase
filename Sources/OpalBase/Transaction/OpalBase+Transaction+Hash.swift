// OpalBase+Transaction+Hash.swift

import Foundation

extension _OpalBase.Transaction {
    public struct Hash {
        static let expectedByteCount = 32
        public let originalData: Data
        
        // Initializer for data received in natural order (little-endian)
        public init(naturalOrder data: Data) {
            self.originalData = data
        }
        
        // Initializer for data received in reverse order (big-endian)
        public init(reverseOrder data: Data) {
            self.originalData = data.reversedData // Convert to natural order
        }
        
        public init(dataFromBlockExplorer data: Data) {
            self.originalData = data.reversedData
        }
        
        public init(dataFromRPC data: Data) {
            self.originalData = data.reversedData
        }
        
        // Computed property to return the natural byte order (little-endian)
        public var naturalOrder: Data {
            return originalData
        }
        
        // Computed property to return the reverse byte order (big-endian)
        public var reverseOrder: Data {
            return originalData.reversedData
        }
        
        // Computed property to return the little-endian format
        public var littleEndian: Data {
            return originalData
        }
        
        // Computed property to return the big-endian format
        public var bigEndian: Data {
            return reverseOrder
        }
        
        // Alias for internal usage in the Bitcoin protocol
        public var internallyUsedFormat: Data {
            return naturalOrder
        }
        
        // Alias for external usage (e.g., block explorers, RPC servers)
        public var externallyUsedFormat: Data {
            return reverseOrder
        }
        
        // Alias for compatibility with block explorers
        public var compatibleWithBlockExplorerOrder: Data {
            return reverseOrder
        }
    }
}

extension _OpalBase.Transaction.Hash: CustomStringConvertible {
    public var description: String {
        "\(naturalOrder.hexadecimalString) (↔︎: \(reverseOrder.hexadecimalString))"
    }
}

extension _OpalBase.Transaction.Hash: Sendable {}
extension _OpalBase.Transaction.Hash: Hashable {}
extension _OpalBase.Transaction.Hash: Codable {
    private enum CodingKeys: String, CodingKey {
        case originalData
    }

    private static func invalidByteCountDescription(actual: Int) -> String {
        "Invalid transaction hash length: expected \(Self.expectedByteCount) bytes, got \(actual)"
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let originalData = try container.decode(Data.self, forKey: .originalData)
        guard originalData.count == Self.expectedByteCount else {
            throw DecodingError.dataCorruptedError(
                forKey: .originalData,
                in: container,
                debugDescription: Self.invalidByteCountDescription(actual: originalData.count)
            )
        }
        self.init(naturalOrder: originalData)
    }

    public func encode(to encoder: Encoder) throws {
        guard originalData.count == Self.expectedByteCount else {
            throw EncodingError.invalidValue(
                originalData,
                .init(
                    codingPath: encoder.codingPath + [CodingKeys.originalData],
                    debugDescription: Self.invalidByteCountDescription(actual: originalData.count)
                )
            )
        }
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(originalData, forKey: .originalData)
    }
}
