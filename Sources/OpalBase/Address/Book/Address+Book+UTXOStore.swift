// Address+Book+UTXOStore.swift

import Foundation

extension Address.Book {
    struct UTXOStore {
        private var utxos: Set<Transaction.Output.Unspent>
        
        init() {
            self.utxos = .init()
        }
        
        mutating func add(_ utxo: Transaction.Output.Unspent) {
            utxos.insert(utxo)
        }
        
        mutating func add(_ utxos: [Transaction.Output.Unspent]) {
            self.utxos.formUnion(utxos)
        }
        
        mutating func replace(with utxos: Set<Transaction.Output.Unspent>) {
            self.utxos = utxos
        }
        
        mutating func replace(for address: Address, with utxos: [Transaction.Output.Unspent]) {
            let lockingScript = address.lockingScript.data
            let existingMatches = self.utxos.filter { $0.lockingScript == lockingScript }
            if !existingMatches.isEmpty {
                self.utxos.subtract(existingMatches)
            }
            if !utxos.isEmpty {
                self.utxos.formUnion(utxos)
            }
        }
        
        mutating func remove(_ utxo: Transaction.Output.Unspent) {
            utxos.remove(utxo)
        }
        
        mutating func remove(_ utxos: [Transaction.Output.Unspent]) {
            self.utxos.subtract(utxos)
        }
        
        mutating func clear() {
            utxos.removeAll()
        }
        
        func list() -> Set<Transaction.Output.Unspent> {
            utxos
        }
        
        func sorted(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool)
        -> [Transaction.Output.Unspent] {
            utxos.sorted(by: areInIncreasingOrder)
        }
        
        func utxo(matching input: Transaction.Input) -> Transaction.Output.Unspent? {
            utxos.first(where: { unspent in
                unspent.previousTransactionHash == input.previousTransactionHash &&
                unspent.previousTransactionOutputIndex == input.previousTransactionOutputIndex
            })
        }
    }
}

extension Address.Book.UTXOStore: Sendable {}
