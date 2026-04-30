// OpalBase+Address+Book+UTXORepository.swift

import Foundation

extension _OpalBase.Address.Book {
    struct UTXORepository {
        struct Outpoint: Hashable, Sendable {
            let transactionHash: OpalBase.Transaction.Hash
            let outputIndex: UInt32
            
            init(_ input: OpalBase.Transaction.Input) {
                self.transactionHash = input.previousTransactionHash
                self.outputIndex = input.previousTransactionOutputIndex
            }
            
            init(_ utxo: OpalBase.Transaction.Output.Unspent) {
                self.transactionHash = utxo.previousTransactionHash
                self.outputIndex = utxo.previousTransactionOutputIndex
            }
        }
        
        var utxosByLockingScript: [Data: Set<OpalBase.Transaction.Output.Unspent>]
        var utxosByOutpoint: [Outpoint: OpalBase.Transaction.Output.Unspent]
        var reservedUTXOs: Set<OpalBase.Transaction.Output.Unspent>
        
        init() {
            self.utxosByLockingScript = .init()
            self.utxosByOutpoint = .init()
            self.reservedUTXOs = .init()
        }
        
        mutating func add(_ utxo: OpalBase.Transaction.Output.Unspent) {
            store(utxo)
        }
        
        mutating func add(_ utxos: [OpalBase.Transaction.Output.Unspent]) {
            guard !utxos.isEmpty else {
                return
            }
            
            for utxo in utxos {
                store(utxo)
            }
        }
        
        mutating func replace(with utxos: Set<OpalBase.Transaction.Output.Unspent>) {
            utxosByLockingScript = utxos.reduce(into: [Data: Set<OpalBase.Transaction.Output.Unspent>]()) { result, unspent in
                result[unspent.lockingScript, default: .init()].insert(unspent)
            }
            utxosByOutpoint = utxos.reduce(into: .init()) { result, unspent in
                result[Outpoint(unspent)] = unspent
            }
            reservedUTXOs = reservedUTXOs.intersection(utxos)
        }
        
        mutating func replace(for address: OpalBase.Address, with utxos: [OpalBase.Transaction.Output.Unspent]) {
            let lockingScript = address.lockingScript.data
            let newUTXOs = Set(utxos)
            
            if let oldUTXOs = utxosByLockingScript[lockingScript] {
                for utxo in oldUTXOs {
                    utxosByOutpoint.removeValue(forKey: Outpoint(utxo))
                    reservedUTXOs.remove(utxo)
                }
            }
            
            if newUTXOs.isEmpty {
                utxosByLockingScript.removeValue(forKey: lockingScript)
            } else {
                utxosByLockingScript[lockingScript] = newUTXOs
                for utxo in newUTXOs {
                    utxosByOutpoint[Outpoint(utxo)] = utxo
                }
            }
            
            reservedUTXOs = reservedUTXOs.intersection(allUTXOs)
        }
        
        mutating func remove(_ utxo: OpalBase.Transaction.Output.Unspent) {
            discard(utxo)
            reservedUTXOs.remove(utxo)
        }
        
        mutating func remove(_ utxos: [OpalBase.Transaction.Output.Unspent]) {
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
            utxosByOutpoint.removeAll()
            reservedUTXOs.removeAll()
        }
        
        mutating func reserve(_ utxos: Set<OpalBase.Transaction.Output.Unspent>) throws {
            try reserve(utxos, tokenSelectionPolicy: .allowTokenUTXOs)
        }
        
        mutating func reserve(_ utxos: Set<OpalBase.Transaction.Output.Unspent>,
                              tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy) throws {
            let allowedUTXOs = filterUTXOs(allUTXOs, tokenSelectionPolicy: tokenSelectionPolicy)
            guard utxos.isSubset(of: allowedUTXOs) else { throw OpalBase.Address.Book.Error.utxoNotFound }
            
            if let conflict = reservedUTXOs.intersection(utxos).first {
                throw OpalBase.Address.Book.Error.utxoAlreadyReserved(conflict)
            }
            
            reservedUTXOs.formUnion(utxos)
        }
        
        mutating func release(_ utxos: Set<OpalBase.Transaction.Output.Unspent>) {
            guard !utxos.isEmpty else { return }
            reservedUTXOs.subtract(utxos)
        }
        
        func findUTXO(matching input: OpalBase.Transaction.Input) -> OpalBase.Transaction.Output.Unspent? {
            utxosByOutpoint[Outpoint(input)]
        }
        
        private mutating func store(_ utxo: OpalBase.Transaction.Output.Unspent) {
            let outpoint = Outpoint(utxo)
            var shouldRestoreReservation = false
            if let existing = utxosByOutpoint[outpoint] {
                shouldRestoreReservation = reservedUTXOs.contains(existing)
                discard(existing)
                reservedUTXOs.remove(existing)
            }

            var utxos = utxosByLockingScript[utxo.lockingScript] ?? .init()
            utxos.insert(utxo)
            utxosByLockingScript[utxo.lockingScript] = utxos
            utxosByOutpoint[outpoint] = utxo
            if shouldRestoreReservation {
                reservedUTXOs.insert(utxo)
            }
        }
        
        private mutating func discard(_ utxo: OpalBase.Transaction.Output.Unspent) {
            guard var indexedUTXOs = utxosByLockingScript[utxo.lockingScript] else {
                return
            }
            
            indexedUTXOs.remove(utxo)
            
            if indexedUTXOs.isEmpty {
                utxosByLockingScript.removeValue(forKey: utxo.lockingScript)
            } else {
                utxosByLockingScript[utxo.lockingScript] = indexedUTXOs
            }
            
            utxosByOutpoint.removeValue(forKey: Outpoint(utxo))
        }
    }
}

extension _OpalBase.Address.Book.UTXORepository: Sendable {}
