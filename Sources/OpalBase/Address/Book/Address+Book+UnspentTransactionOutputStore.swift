// Address+Book+UnspentTransactionOutputStore.swift

import Foundation

extension Address.Book {
    struct UnspentTransactionOutputStore {
        private var unspentTransactionOutputs: Set<Transaction.Output.Unspent>
        
        init() {
            self.unspentTransactionOutputs = .init()
        }
        
        mutating func add(_ unspentTransactionOutput: Transaction.Output.Unspent) {
            unspentTransactionOutputs.insert(unspentTransactionOutput)
        }
        
        mutating func add(_ unspentTransactionOutputs: [Transaction.Output.Unspent]) {
            self.unspentTransactionOutputs.formUnion(unspentTransactionOutputs)
        }
        
        mutating func replace(with unspentTransactionOutputs: Set<Transaction.Output.Unspent>) {
            self.unspentTransactionOutputs = unspentTransactionOutputs
        }
        
        mutating func replace(for address: Address, with unspentTransactionOutputs: [Transaction.Output.Unspent]) {
            let lockingScript = address.lockingScript.data
            let existingMatches = self.unspentTransactionOutputs.filter { $0.lockingScript == lockingScript }
            if !existingMatches.isEmpty {
                self.unspentTransactionOutputs.subtract(existingMatches)
            }
            if !unspentTransactionOutputs.isEmpty {
                self.unspentTransactionOutputs.formUnion(unspentTransactionOutputs)
            }
        }
        
        mutating func remove(_ unspentTransactionOutput: Transaction.Output.Unspent) {
            unspentTransactionOutputs.remove(unspentTransactionOutput)
        }
        
        mutating func remove(_ unspentTransactionOutputs: [Transaction.Output.Unspent]) {
            self.unspentTransactionOutputs.subtract(unspentTransactionOutputs)
        }
        
        mutating func clear() {
            unspentTransactionOutputs.removeAll()
        }
        
        func listUnspentTransactionOutputs() -> Set<Transaction.Output.Unspent> {
            unspentTransactionOutputs
        }
        
        func sorted(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool)
        -> [Transaction.Output.Unspent] {
            unspentTransactionOutputs.sorted(by: areInIncreasingOrder)
        }
        
        func findUnspentTransactionOutput(matching input: Transaction.Input) -> Transaction.Output.Unspent? {
            unspentTransactionOutputs.first(where: { unspent in
                unspent.previousTransactionHash == input.previousTransactionHash &&
                unspent.previousTransactionOutputIndex == input.previousTransactionOutputIndex
            })
        }
    }
}

extension Address.Book.UnspentTransactionOutputStore: Sendable {}
