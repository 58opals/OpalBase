// Address+Book+UTXOStore.swift

import Foundation

extension Address.Book {
    public struct UTXOStore {
        private var utxosByLockingScript: [Data: Set<Transaction.Output.Unspent>]
        private var reservedUTXOs: Set<Transaction.Output.Unspent>
        
        init() {
            self.utxosByLockingScript = .init()
            self.reservedUTXOs = .init()
        }
        
        mutating func add(_ utxo: Transaction.Output.Unspent) {
            store(utxo)
        }
        
        mutating func add(_ utxos: [Transaction.Output.Unspent]) {
            guard !utxos.isEmpty else {
                return
            }
            
            for utxo in utxos {
                store(utxo)
            }
        }
        
        mutating func replace(with utxos: Set<Transaction.Output.Unspent>) {
            utxosByLockingScript = utxos.reduce(into: [Data: Set<Transaction.Output.Unspent>]()) { result, unspent in
                result[unspent.lockingScript, default: .init()].insert(unspent)
            }
            
            reservedUTXOs = reservedUTXOs.intersection(utxos)
        }
        
        mutating func replace(for address: Address, with utxos: [Transaction.Output.Unspent]) {
            let lockingScript = address.lockingScript.data
            let newUTXOs = Set(utxos)
            
            if newUTXOs.isEmpty {
                utxosByLockingScript.removeValue(forKey: lockingScript)
            } else {
                utxosByLockingScript[lockingScript] = newUTXOs
            }
            
            reservedUTXOs = reservedUTXOs.intersection(allUTXOs)
        }
        
        mutating func remove(_ utxo: Transaction.Output.Unspent) {
            discard(utxo)
            reservedUTXOs.remove(utxo)
        }
        
        mutating func remove(_ utxos: [Transaction.Output.Unspent]) {
            let removals = Set(utxos)
            guard !removals.isEmpty else {
                return
            }
            
            for removal in removals {
                discard(removal)
                reservedUTXOs.remove(removal)
            }
        }
        
        mutating func clear() {
            utxosByLockingScript.removeAll()
            reservedUTXOs.removeAll()
        }
        
        mutating func reserve(_ utxos: Set<Transaction.Output.Unspent>) throws {
            guard utxos.isSubset(of: allUTXOs) else { throw Address.Book.Error.utxoNotFound }
            
            if let conflict = reservedUTXOs.intersection(utxos).first {
                throw Address.Book.Error.utxoAlreadyReserved(conflict)
            }
            
            reservedUTXOs.formUnion(utxos)
        }
        
        mutating func release(_ utxos: Set<Transaction.Output.Unspent>) {
            guard !utxos.isEmpty else { return }
            reservedUTXOs.subtract(utxos)
        }
        
        func listUTXOs() -> Set<Transaction.Output.Unspent> {
            allUTXOs
        }
        
        func sorted(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool)
        -> [Transaction.Output.Unspent] {
            allUTXOs.sorted(by: areInIncreasingOrder)
        }
        
        func sortedSpendable(by areInIncreasingOrder: (Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool)
        -> [Transaction.Output.Unspent] {
            spendableUTXOs.sorted(by: areInIncreasingOrder)
        }
        
        func findUTXO(matching input: Transaction.Input) -> Transaction.Output.Unspent? {
            for utxos in utxosByLockingScript.values {
                if let match = utxos.first(where: { unspent in
                    unspent.previousTransactionHash == input.previousTransactionHash &&
                    unspent.previousTransactionOutputIndex == input.previousTransactionOutputIndex
                }) {
                    return match
                }
            }
            
            return nil
        }
        
        private var allUTXOs: Set<Transaction.Output.Unspent> {
            utxosByLockingScript.values.reduce(into: Set<Transaction.Output.Unspent>()) { result, utxos in
                result.formUnion(utxos)
            }
        }
        
        private var spendableUTXOs: Set<Transaction.Output.Unspent> {
            var spendable = allUTXOs
            spendable.subtract(reservedUTXOs)
            return spendable
        }
        
        private mutating func store(_ utxo: Transaction.Output.Unspent) {
            var utxos = utxosByLockingScript[utxo.lockingScript] ?? .init()
            utxos.insert(utxo)
            utxosByLockingScript[utxo.lockingScript] = utxos
        }
        
        private mutating func discard(_ utxo: Transaction.Output.Unspent) {
            guard var indexedUTXOs = utxosByLockingScript[utxo.lockingScript] else {
                return
            }
            
            indexedUTXOs.remove(utxo)
            
            if indexedUTXOs.isEmpty {
                utxosByLockingScript.removeValue(forKey: utxo.lockingScript)
            } else {
                utxosByLockingScript[utxo.lockingScript] = indexedUTXOs
            }
        }
    }
}

extension Address.Book.UTXOStore: Sendable {}

extension Address.Book {
    func reserveUTXOs(_ utxos: Set<Transaction.Output.Unspent>) throws {
        try utxoStore.reserve(utxos)
    }
    
    func releaseUTXOs(_ utxos: Set<Transaction.Output.Unspent>) {
        utxoStore.release(utxos)
    }
    
    func addUTXO(_ utxo: Transaction.Output.Unspent) {
        utxoStore.add(utxo)
    }
    
    func addUTXOs(_ utxos: [Transaction.Output.Unspent]) {
        utxoStore.add(utxos)
    }
    
    func listUTXOs() -> Set<Transaction.Output.Unspent> {
        utxoStore.listUTXOs()
    }
    
    func replaceUTXOs(with utxos: Set<Transaction.Output.Unspent>) {
        utxoStore.replace(with: utxos)
    }
    
    func replaceUTXOs(for address: Address, with utxos: [Transaction.Output.Unspent]) {
        utxoStore.replace(for: address, with: utxos)
    }
    
    func removeUTXO(_ utxo: Transaction.Output.Unspent) {
        utxoStore.remove(utxo)
    }
    
    func findUTXO(matching input: Transaction.Input) -> Transaction.Output.Unspent? {
        utxoStore.findUTXO(matching: input)
    }
    
    func sortedUTXOs(by areInIncreasingOrder: (Transaction.Output.Unspent,
                                               Transaction.Output.Unspent) -> Bool)
    -> [Transaction.Output.Unspent] {
        utxoStore.sorted(by: areInIncreasingOrder)
    }
    
    func sortedSpendableUTXOs(by areInIncreasingOrder: ((Transaction.Output.Unspent, Transaction.Output.Unspent) -> Bool))
    -> [Transaction.Output.Unspent] {
        utxoStore.sortedSpendable(by: areInIncreasingOrder)
    }
}
