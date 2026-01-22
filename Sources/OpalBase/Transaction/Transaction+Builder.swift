// Transaction+Builder.swift

import Foundation

extension Transaction {
    struct Builder {
        let orderedUnspentOutputs: [Transaction.Output.Unspent]
        let signatureFormat: ECDSA.SignatureFormat
        let sequence: UInt32
        
        private let privateKeysByUnspent: [Transaction.Output.Unspent: PrivateKey]
        private let unlockersByUnspent: [Transaction.Output.Unspent: Transaction.Unlocker]
        
        init(utxoPrivateKeyPairs: [Transaction.Output.Unspent: PrivateKey],
             signatureFormat: ECDSA.SignatureFormat,
             sequence: UInt32,
             unlockers: [Transaction.Output.Unspent: Transaction.Unlocker]) {
            self.privateKeysByUnspent = utxoPrivateKeyPairs
            self.signatureFormat = signatureFormat
            self.sequence = sequence
            self.unlockersByUnspent = unlockers
            
            self.orderedUnspentOutputs = utxoPrivateKeyPairs.keys.sorted { lhs, rhs in
                let lhsHash = lhs.previousTransactionHash.reverseOrder
                let rhsHash = rhs.previousTransactionHash.reverseOrder
                // BIP-69 specifies ordering inputs by the transaction hash as displayed externally (big-endian). `Transaction.Hash.reverseOrder` exposes that representation, while `naturalOrder` returns the little-endian form used internally. Sorting by the wrong byte order would invert the expected ordering for inputs whose hashes differ only in high-order bytes, producing non-deterministic builders across implementations.
                
                if lhsHash != rhsHash {
                    return lhsHash.lexicographicallyPrecedes(rhsHash)
                }
                
                if lhs.previousTransactionOutputIndex != rhs.previousTransactionOutputIndex {
                    return lhs.previousTransactionOutputIndex < rhs.previousTransactionOutputIndex
                }
                
                if lhs.value != rhs.value {
                    return lhs.value < rhs.value
                }
                
                return lhs.lockingScript.lexicographicallyPrecedes(rhs.lockingScript)
            }
        }
        
        func makeInputs() -> [Transaction.Input] {
            orderedUnspentOutputs.map { unspentOutput in
                let unlocker = makeUnlocker(for: unspentOutput)
                let placeholder = unlocker.makePlaceholderUnlockingScript(signatureFormat: signatureFormat)
                return Transaction.Input(previousTransactionHash: unspentOutput.previousTransactionHash,
                                         previousTransactionOutputIndex: unspentOutput.previousTransactionOutputIndex,
                                         unlockingScript: placeholder,
                                         sequence: sequence)
            }
        }
        
        func makeUnlocker(for unspentOutput: Transaction.Output.Unspent) -> Transaction.Unlocker {
            unlockersByUnspent[unspentOutput] ?? .p2pkh_CheckSig()
        }
        
        func findPrivateKey(for unspentOutput: Transaction.Output.Unspent) -> PrivateKey? {
            privateKeysByUnspent[unspentOutput]
        }
    }
}
