// Transaction+Output~Order.swift

import Foundation

extension Transaction.Output {
    /// Returns the provided outputs ordered according to BIP-69.
    ///
    /// The specification requires sorting by the output value (ascending) and
    /// using the locking script bytes as a lexicographic tie breaker. Applying
    /// this ordering yields deterministic transactions that are compatible with
    /// downstream tooling expecting canonical output layouts.
    /// - Parameter outputs: The outputs to be ordered.
    /// - Returns: The outputs sorted according to the canonical BIP-69 rules.
    static func applyBIP69Ordering(_ outputs: [Transaction.Output]) -> [Transaction.Output] {
        outputs.sorted { lhs, rhs in
            if lhs.value != rhs.value {
                return lhs.value < rhs.value
            }
            
            return lhs.lockingScript.lexicographicallyPrecedes(rhs.lockingScript)
        }
    }
}
