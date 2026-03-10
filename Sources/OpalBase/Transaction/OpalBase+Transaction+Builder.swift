// OpalBase+Transaction+Builder.swift

import Foundation
import OpalCrypto

extension _OpalBase.Transaction {
    struct Builder {
        let orderedUnspentOutputs: [OpalBase.Transaction.Output.Unspent]
        let signatureFormat: OpalCrypto.Signature.Format
        let sequence: UInt32
        
        private let privateKeysByUnspent: [OpalBase.Transaction.Output.Unspent: Data]
        private let unlockersByUnspent: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker]
        
        init(utxoPrivateKeyPairs: [OpalBase.Transaction.Output.Unspent: Data],
             signatureFormat: OpalCrypto.Signature.Format,
             sequence: UInt32,
             unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker]) {
            self.privateKeysByUnspent = utxoPrivateKeyPairs
            self.signatureFormat = signatureFormat
            self.sequence = sequence
            self.unlockersByUnspent = unlockers
            
            self.orderedUnspentOutputs = utxoPrivateKeyPairs.keys.sorted { lhs, rhs in
                let lhsHash = lhs.previousTransactionHash.reverseOrder
                let rhsHash = rhs.previousTransactionHash.reverseOrder
                // BIP-69 specifies ordering inputs by the transaction hash as displayed externally (big-endian). `OpalBase.Transaction.Hash.reverseOrder` exposes that representation, while `naturalOrder` returns the little-endian form used internally. Sorting by the wrong byte order would invert the expected ordering for inputs whose hashes differ only in high-order bytes, producing non-deterministic builders across implementations.
                
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
        
        func makeInputs() -> [OpalBase.Transaction.Input] {
            orderedUnspentOutputs.map { unspentOutput in
                let unlocker = makeUnlocker(for: unspentOutput)
                let placeholder = unlocker.makePlaceholderUnlockingScript(signatureFormat: signatureFormat)
                return OpalBase.Transaction.Input(previousTransactionHash: unspentOutput.previousTransactionHash,
                                         previousTransactionOutputIndex: unspentOutput.previousTransactionOutputIndex,
                                         unlockingScript: placeholder,
                                         sequence: sequence)
            }
        }
        
        func makeUnlocker(for unspentOutput: OpalBase.Transaction.Output.Unspent) -> OpalBase.Transaction.Unlocker {
            unlockersByUnspent[unspentOutput] ?? .p2pkh_CheckSig()
        }
        
        func findPrivateKey(for unspentOutput: OpalBase.Transaction.Output.Unspent) -> Data? {
            privateKeysByUnspent[unspentOutput]
        }
    }
}
