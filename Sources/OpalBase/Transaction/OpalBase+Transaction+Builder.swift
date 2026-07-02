// OpalBase+Transaction+Builder.swift

import Foundation

extension _OpalBase.Transaction {
    struct Builder {
        let orderedUnspentOutputs: [OpalBase.Transaction.Output.Unspent]
        let signatureFormat: OpalBase.Transaction.SignatureFormat
        let sequence: UInt32
        
        private let signingKeysByUnspent: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey]
        private let unlockersByUnspent: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker]
        
        init(utxoSigningKeyPairs: [OpalBase.Transaction.Output.Unspent: OpalBase.Key.SigningKey],
             signatureFormat: OpalBase.Transaction.SignatureFormat,
             sequence: UInt32,
             unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker]) {
            self.signingKeysByUnspent = utxoSigningKeyPairs
            self.signatureFormat = signatureFormat
            self.sequence = sequence
            self.unlockersByUnspent = unlockers
            self.orderedUnspentOutputs = Self.orderUnspentOutputs(utxoSigningKeyPairs.keys)
        }

        init(unspentOutputs: [OpalBase.Transaction.Output.Unspent],
             signatureFormat: OpalBase.Transaction.SignatureFormat,
             sequence: UInt32,
             unlockers: [OpalBase.Transaction.Output.Unspent: OpalBase.Transaction.Unlocker]) {
            self.signingKeysByUnspent = .init()
            self.signatureFormat = signatureFormat
            self.sequence = sequence
            self.unlockersByUnspent = unlockers
            self.orderedUnspentOutputs = Self.orderUnspentOutputs(unspentOutputs)
        }

        private static func orderUnspentOutputs<S: Sequence>(
            _ unspentOutputs: S
        ) -> [OpalBase.Transaction.Output.Unspent] where S.Element == OpalBase.Transaction.Output.Unspent {
            unspentOutputs.sorted { lhs, rhs in
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
        
        func findSigningKey(for unspentOutput: OpalBase.Transaction.Output.Unspent) -> OpalBase.Key.SigningKey? {
            signingKeysByUnspent[unspentOutput]
        }

        func requireUnlockerKeysMatchUnspentOutputs() throws {
            for unlockerUnspentOutput in unlockersByUnspent.keys {
                guard orderedUnspentOutputs.contains(where: {
                    Self.matchesExactUnspentOutputPayload($0, unlockerUnspentOutput)
                }) else {
                    throw OpalBase.Transaction.Error.cannotCreateTransaction
                }
            }
        }

        private static func matchesExactUnspentOutputPayload(
            _ lhs: OpalBase.Transaction.Output.Unspent,
            _ rhs: OpalBase.Transaction.Output.Unspent
        ) -> Bool {
            lhs.hasSameOutpointAndPayload(as: rhs)
        }
    }
}
