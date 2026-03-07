// AddressModel+BookActor~PrivateKey.swift

import Foundation

extension AddressModel.BookActor {
    private func loadPrivateKey(for address: AddressModel) throws -> PrivateKeyModel {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        let privateKey = try generatePrivateKey(at: entry.derivationPath.index,
                                                for: entry.derivationPath.usage)
        return privateKey
    }
    
    func derivePrivateKeys(for utxos: [TransactionModel.OutputModel.UnspentModel]) throws -> [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel] {
        var derived: [TransactionModel.OutputModel.UnspentModel: PrivateKeyModel] = .init()
        derived.reserveCapacity(utxos.count)
        
        var addressByLockingScript: [Data: AddressModel] = .init()
        addressByLockingScript.reserveCapacity(utxos.count)
        
        var privateKeyByAddress: [AddressModel: PrivateKeyModel] = .init()
        privateKeyByAddress.reserveCapacity(utxos.count)
        
        for utxo in utxos {
            let lockingScript = utxo.lockingScript
            let address: AddressModel
            if let cachedAddress = addressByLockingScript[lockingScript] {
                address = cachedAddress
            } else {
                let script = try ScriptModel.decode(lockingScript: lockingScript)
                address = try AddressModel(script: script)
                addressByLockingScript[lockingScript] = address
            }
            
            let privateKey: PrivateKeyModel
            if let cachedPrivateKey = privateKeyByAddress[address] {
                privateKey = cachedPrivateKey
            } else {
                privateKey = try loadPrivateKey(for: address)
                privateKeyByAddress[address] = privateKey
            }
            
            derived[utxo] = privateKey
        }
        
        return derived
    }
}

