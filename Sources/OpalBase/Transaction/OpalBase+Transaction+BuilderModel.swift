// OpalBase.Transaction+BuilderModel.swift

import Foundation

extension _OpalBase.Transaction {
    struct BuilderModel {
        let orderedUnspentOutputs: [OpalBase.Transaction.OutputModel.UnspentModel]
        let signatureFormat: ECDSAModel.SignatureFormatModel
        let sequence: UInt32
        
        private let privateKeysByUnspent: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey]
        private let unlockersByUnspent: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.Transaction.UnlockerModel]
        
        init(utxoPrivateKeyPairs: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.PrivateKey],
             signatureFormat: ECDSAModel.SignatureFormatModel,
             sequence: UInt32,
             unlockers: [OpalBase.Transaction.OutputModel.UnspentModel: OpalBase.Transaction.UnlockerModel]) {
            self.privateKeysByUnspent = utxoPrivateKeyPairs
            self.signatureFormat = signatureFormat
            self.sequence = sequence
            self.unlockersByUnspent = unlockers
            
            self.orderedUnspentOutputs = utxoPrivateKeyPairs.keys.sorted { lhs, rhs in
                let lhsHash = lhs.previousTransactionHash.reverseOrder
                let rhsHash = rhs.previousTransactionHash.reverseOrder
                // BIP-69 specifies ordering inputs by the transaction hash as displayed externally (big-endian). `OpalBase.Transaction.HashModel.reverseOrder` exposes that representation, while `naturalOrder` returns the little-endian form used internally. Sorting by the wrong byte order would invert the expected ordering for inputs whose hashes differ only in high-order bytes, producing non-deterministic builders across implementations.
                
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
        
        func makeInputs() -> [OpalBase.Transaction.InputModel] {
            orderedUnspentOutputs.map { unspentOutput in
                let unlocker = makeUnlocker(for: unspentOutput)
                let placeholder = unlocker.makePlaceholderUnlockingScript(signatureFormat: signatureFormat)
                return OpalBase.Transaction.InputModel(previousTransactionHash: unspentOutput.previousTransactionHash,
                                         previousTransactionOutputIndex: unspentOutput.previousTransactionOutputIndex,
                                         unlockingScript: placeholder,
                                         sequence: sequence)
            }
        }
        
        func makeUnlocker(for unspentOutput: OpalBase.Transaction.OutputModel.UnspentModel) -> OpalBase.Transaction.UnlockerModel {
            unlockersByUnspent[unspentOutput] ?? .p2pkh_CheckSig()
        }
        
        func findPrivateKey(for unspentOutput: OpalBase.Transaction.OutputModel.UnspentModel) -> OpalBase.PrivateKey? {
            privateKeysByUnspent[unspentOutput]
        }
    }
}
