// TransactionModel+BuilderModel.swift

import Foundation

extension TransactionModel {
    struct BuilderModel {
        let orderedUnspentOutputs: [TransactionModel.OutputModel.UnspentModel]
        let signatureFormat: ECDSAModel.SignatureFormatModel
        let sequence: UInt32
        
        private let privateKeysByUnspent: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel]
        private let unlockersByUnspent: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel]
        
        init(utxoPrivateKeyPairs: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel],
             signatureFormat: ECDSAModel.SignatureFormatModel,
             sequence: UInt32,
             unlockers: [TransactionModel.OutputModel.UnspentModel: TransactionModel.UnlockerModel]) {
            self.privateKeysByUnspent = utxoPrivateKeyPairs
            self.signatureFormat = signatureFormat
            self.sequence = sequence
            self.unlockersByUnspent = unlockers
            
            self.orderedUnspentOutputs = utxoPrivateKeyPairs.keys.sorted { lhs, rhs in
                let lhsHash = lhs.previousTransactionHash.reverseOrder
                let rhsHash = rhs.previousTransactionHash.reverseOrder
                // BIP-69 specifies ordering inputs by the transaction hash as displayed externally (big-endian). `TransactionModel.HashModel.reverseOrder` exposes that representation, while `naturalOrder` returns the little-endian form used internally. Sorting by the wrong byte order would invert the expected ordering for inputs whose hashes differ only in high-order bytes, producing non-deterministic builders across implementations.
                
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
        
        func makeInputs() -> [TransactionModel.InputModel] {
            orderedUnspentOutputs.map { unspentOutput in
                let unlocker = makeUnlocker(for: unspentOutput)
                let placeholder = unlocker.makePlaceholderUnlockingScript(signatureFormat: signatureFormat)
                return TransactionModel.InputModel(previousTransactionHash: unspentOutput.previousTransactionHash,
                                         previousTransactionOutputIndex: unspentOutput.previousTransactionOutputIndex,
                                         unlockingScript: placeholder,
                                         sequence: sequence)
            }
        }
        
        func makeUnlocker(for unspentOutput: TransactionModel.OutputModel.UnspentModel) -> TransactionModel.UnlockerModel {
            unlockersByUnspent[unspentOutput] ?? .p2pkh_CheckSig()
        }
        
        func findPrivateKey(for unspentOutput: TransactionModel.OutputModel.UnspentModel) -> PrivateKeyModel? {
            privateKeysByUnspent[unspentOutput]
        }
    }
}
