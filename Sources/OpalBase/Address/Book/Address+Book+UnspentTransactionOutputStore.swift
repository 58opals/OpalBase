// Address+Book+UnspentTransactionOutputStore.swift

import Foundation

extension Address.Book {
    public struct UnspentTransactionOutputStore {
        private var unspentTransactionOutputsByLockingScript: [Data: Set<Transaction.Output.Unspent>]
        
        init() {
            self.unspentTransactionOutputsByLockingScript = .init()
        }
        
        mutating func add(_ unspentTransactionOutput: Transaction.Output.Unspent) {
            store(unspentTransactionOutput)
        }
        
        mutating func add(_ unspentTransactionOutputs: [Transaction.Output.Unspent]) {
            guard !unspentTransactionOutputs.isEmpty else {
                return
            }
            
            for unspentTransactionOutput in unspentTransactionOutputs {
                store(unspentTransactionOutput)
            }
        }
        
        mutating func replace(with unspentTransactionOutputs: Set<Transaction.Output.Unspent>) {
            unspentTransactionOutputsByLockingScript = unspentTransactionOutputs.reduce(into: [Data: Set<Transaction.Output.Unspent>]()) { result, unspent in
                result[unspent.lockingScript, default: []].insert(unspent)
            }
        }
        
        mutating func replace(for address: Address, with unspentTransactionOutputs: [Transaction.Output.Unspent]) {
            let lockingScript = address.lockingScript.data
            let newUnspentTransactionOutputs = Set(unspentTransactionOutputs)
            
            if newUnspentTransactionOutputs.isEmpty {
                unspentTransactionOutputsByLockingScript.removeValue(forKey: lockingScript)
            } else {
                unspentTransactionOutputsByLockingScript[lockingScript] = newUnspentTransactionOutputs
            }
        }
        
        mutating func remove(_ unspentTransactionOutput: Transaction.Output.Unspent) {
            discard(unspentTransactionOutput)
        }
        
        mutating func remove(_ unspentTransactionOutputs: [Transaction.Output.Unspent]) {
            let removals = Set(unspentTransactionOutputs)
            guard !removals.isEmpty else {
                return
            }
            
            for removal in removals {
                discard(removal)
            }
        }
        
        mutating func clear() {
            unspentTransactionOutputsByLockingScript.removeAll()
        }
        
        func listUnspentTransactionOutputs() -> Set<Transaction.Output.Unspent> {
            allUnspentTransactionOutputs
        }
        
        func sorted(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool)
        -> [Transaction.Output.Unspent] {
            allUnspentTransactionOutputs.sorted(by: areInIncreasingOrder)
        }
        
        func findUnspentTransactionOutput(matching input: Transaction.Input) -> Transaction.Output.Unspent? {
            for unspentTransactionOutputs in unspentTransactionOutputsByLockingScript.values {
                if let match = unspentTransactionOutputs.first(where: { unspent in
                    unspent.previousTransactionHash == input.previousTransactionHash &&
                    unspent.previousTransactionOutputIndex == input.previousTransactionOutputIndex
                }) {
                    return match
                }
            }
            
            return nil
        }
        
        private var allUnspentTransactionOutputs: Set<Transaction.Output.Unspent> {
            unspentTransactionOutputsByLockingScript.values.reduce(into: Set<Transaction.Output.Unspent>()) { result, unspentTransactionOutputs in
                result.formUnion(unspentTransactionOutputs)
            }
        }
        
        private mutating func store(_ unspentTransactionOutput: Transaction.Output.Unspent) {
            unspentTransactionOutputsByLockingScript[unspentTransactionOutput.lockingScript, default: []]
                .insert(unspentTransactionOutput)
        }
        
        private mutating func discard(_ unspentTransactionOutput: Transaction.Output.Unspent) {
            guard var indexedUnspentTransactionOutputs = unspentTransactionOutputsByLockingScript[unspentTransactionOutput.lockingScript] else {
                return
            }
            
            indexedUnspentTransactionOutputs.remove(unspentTransactionOutput)
            
            if indexedUnspentTransactionOutputs.isEmpty {
                unspentTransactionOutputsByLockingScript.removeValue(forKey: unspentTransactionOutput.lockingScript)
            } else {
                unspentTransactionOutputsByLockingScript[unspentTransactionOutput.lockingScript] = indexedUnspentTransactionOutputs
            }
        }
    }
}

extension Address.Book.UnspentTransactionOutputStore: Sendable {}
