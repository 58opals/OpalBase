// Transaction+Hash.swift

import Foundation

extension Transaction {
    public struct Hash {
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
        
        // Alias for external usage (e.g., block explorers, rpc servers)
        public var externallyUsedFormat: Data {
            return reverseOrder
        }
        
        // Alias for compatibility with block explorers
        public var compatibleWithBlockExplorerOrder: Data {
            return reverseOrder
        }
    }
}

extension Transaction.Hash: CustomStringConvertible {
    public var description: String {
        "\(naturalOrder.hexadecimalString) (↔︎: \(reverseOrder.hexadecimalString))"
    }
}

extension Transaction.Hash: Sendable {}
extension Transaction.Hash: Hashable {}
