// OpalBase+Transaction+Output~Order.swift

import Foundation

extension _OpalBase.Transaction.Output {
    /// Returns the provided outputs using BIP-69 value and serialized bytecode ordering.
    /// - Parameter outputs: The outputs to be ordered.
    /// - Returns: The outputs sorted by value, then by the serialized locking
    ///   bytecode field. Token-bearing outputs include their CashTokens prefix
    ///   in that bytecode field.
    static func applyBIP69Ordering(_ outputs: [OpalBase.Transaction.Output]) throws -> [OpalBase.Transaction.Output] {
        let sortableOutputs = try outputs.map { output in
            (output: output, serializedLockingBytecode: try output.serializedLockingBytecodeForOrdering())
        }

        return sortableOutputs.sorted(by: { lhs, rhs in
            if lhs.output.value != rhs.output.value {
                return lhs.output.value < rhs.output.value
            }

            if lhs.serializedLockingBytecode != rhs.serializedLockingBytecode {
                return lhs.serializedLockingBytecode.lexicographicallyPrecedes(rhs.serializedLockingBytecode)
            }

            return false
        }).map(\.output)
    }

    private func serializedLockingBytecodeForOrdering() throws -> Data {
        let tokenPrefixData = try makeTokenPrefixData()
        return tokenPrefixData + lockingScript
    }
}
