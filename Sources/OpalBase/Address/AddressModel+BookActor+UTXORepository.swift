// AddressModel+BookActor+UTXORepository.swift

import Foundation

extension AddressModel.BookActor {
    struct UTXORepository {
        struct Outpoint: Hashable, Sendable {
            let transactionHash: TransactionModel.HashModel
            let outputIndex: UInt32
            
            init(_ input: TransactionModel.InputModel) {
                self.transactionHash = input.previousTransactionHash
                self.outputIndex = input.previousTransactionOutputIndex
            }
            
            init(_ utxo: TransactionModel.OutputModel.UnspentModel) {
                self.transactionHash = utxo.previousTransactionHash
                self.outputIndex = utxo.previousTransactionOutputIndex
            }
        }
        
        var utxosByLockingScript: [Data: Set<TransactionModel.OutputModel.UnspentModel>]
        var utxosByOutpoint: [Outpoint: TransactionModel.OutputModel.UnspentModel]
        var reservedUTXOs: Set<TransactionModel.OutputModel.UnspentModel>
        
        init() {
            self.utxosByLockingScript = .init()
            self.utxosByOutpoint = .init()
            self.reservedUTXOs = .init()
        }
        
        mutating func add(_ utxo: TransactionModel.OutputModel.UnspentModel) {
            store(utxo)
        }
        
        mutating func add(_ utxos: [TransactionModel.OutputModel.UnspentModel]) {
            guard !utxos.isEmpty else {
                return
            }
            
            for utxo in utxos {
                store(utxo)
            }
        }
        
        mutating func replace(with utxos: Set<TransactionModel.OutputModel.UnspentModel>) {
            utxosByLockingScript = utxos.reduce(into: [Data: Set<TransactionModel.OutputModel.UnspentModel>]()) { result, unspent in
                result[unspent.lockingScript, default: .init()].insert(unspent)
            }
            utxosByOutpoint = utxos.reduce(into: .init()) { result, unspent in
                result[Outpoint(unspent)] = unspent
            }
            reservedUTXOs = reservedUTXOs.intersection(utxos)
        }
        
        mutating func replace(for address: AddressModel, with utxos: [TransactionModel.OutputModel.UnspentModel]) {
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
        
        mutating func remove(_ utxo: TransactionModel.OutputModel.UnspentModel) {
            discard(utxo)
            reservedUTXOs.remove(utxo)
        }
        
        mutating func remove(_ utxos: [TransactionModel.OutputModel.UnspentModel]) {
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
        
        mutating func reserve(_ utxos: Set<TransactionModel.OutputModel.UnspentModel>) throws {
            try reserve(utxos, tokenSelectionPolicy: .allowTokenUTXOs)
        }
        
        mutating func reserve(_ utxos: Set<TransactionModel.OutputModel.UnspentModel>,
                              tokenSelectionPolicy: AddressModel.BookActor.CoinSelectionModel.TokenSelectionPolicy) throws {
            let allowedUTXOs = filterUTXOs(allUTXOs, tokenSelectionPolicy: tokenSelectionPolicy)
            guard utxos.isSubset(of: allowedUTXOs) else { throw AddressModel.BookActor.Error.utxoNotFound }
            
            if let conflict = reservedUTXOs.intersection(utxos).first {
                throw AddressModel.BookActor.Error.utxoAlreadyReserved(conflict)
            }
            
            reservedUTXOs.formUnion(utxos)
        }
        
        mutating func release(_ utxos: Set<TransactionModel.OutputModel.UnspentModel>) {
            guard !utxos.isEmpty else { return }
            reservedUTXOs.subtract(utxos)
        }
        
        func findUTXO(matching input: TransactionModel.InputModel) -> TransactionModel.OutputModel.UnspentModel? {
            utxosByOutpoint[Outpoint(input)]
        }
        
        private mutating func store(_ utxo: TransactionModel.OutputModel.UnspentModel) {
            var utxos = utxosByLockingScript[utxo.lockingScript] ?? .init()
            utxos.insert(utxo)
            utxosByLockingScript[utxo.lockingScript] = utxos
            utxosByOutpoint[Outpoint(utxo)] = utxo
        }
        
        private mutating func discard(_ utxo: TransactionModel.OutputModel.UnspentModel) {
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

extension AddressModel.BookActor.UTXORepository: Sendable {}
