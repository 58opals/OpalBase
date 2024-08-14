import Foundation

extension Transaction {
    struct Hash {
        let originalData: Data
        
        // Initializer for data received in natural order (little-endian)
        init(naturalOrder data: Data) {
            self.originalData = data
        }

        // Initializer for data received in reverse order (big-endian)
        init(reverseOrder data: Data) {
            self.originalData = data.reversedData // Convert to natural order
        }
        
        init(dataFromBlockExplorer data: Data) {
            self.originalData = data.reversedData
        }
        
        init(dataFromRPC data: Data) {
            self.originalData = data.reversedData
        }

        // Computed property to return the natural byte order (little-endian)
        var naturalOrder: Data {
            return originalData
        }

        // Computed property to return the reverse byte order (big-endian)
        var reverseOrder: Data {
            return originalData.reversedData
        }

        // Computed property to return the little-endian format
        var littleEndian: Data {
            return originalData
        }

        // Computed property to return the big-endian format
        var bigEndian: Data {
            return reverseOrder
        }

        // Alias for internal usage in the Bitcoin protocol
        var internallyUsedFormat: Data {
            return naturalOrder
        }

        // Alias for external usage (e.g., block explorers, rpc servers)
        var externallyUsedFormat: Data {
            return reverseOrder
        }

        // Alias for compatibility with block explorers
        var capableWithBlockExplorerOrder: Data {
            return reverseOrder
        }
    }
}

extension Transaction.Hash: CustomStringConvertible {
    var description: String {
        "\(naturalOrder.hexadecimalString) (↔︎: \(reverseOrder.hexadecimalString))"
    }
}

extension Transaction.Hash: Hashable {}
