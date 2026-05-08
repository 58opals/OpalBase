// OpalBase+Transaction+Output~Order.swift

import Foundation

extension _OpalBase.Transaction.Output {
    /// Returns the provided outputs using BIP-69 value and serialized bytecode ordering.
    /// - Parameter outputs: The outputs to be ordered.
    /// - Returns: The outputs sorted by value, then by the serialized locking
    ///   bytecode field. Token-bearing outputs include their CashTokens prefix
    ///   in that bytecode field.
    static func applyBIP69Ordering(_ outputs: [OpalBase.Transaction.Output]) -> [OpalBase.Transaction.Output] {
        return outputs.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }

            let lhsBytecode = lhs.serializedLockingBytecodeForOrdering
            let rhsBytecode = rhs.serializedLockingBytecodeForOrdering
            if lhsBytecode != rhsBytecode {
                return lhsBytecode.lexicographicallyPrecedes(rhsBytecode)
            }

            return false
        }
    }

    private var serializedLockingBytecodeForOrdering: Data {
        let tokenPrefixData = (try? makeTokenPrefixData()) ?? Data()
        return tokenPrefixData + lockingScript
    }
}
