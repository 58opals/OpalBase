// OpalBase+Address+Book~PrivateKey.swift

import Foundation

extension _OpalBase.Address.Book {
    private func loadPrivateKey(for address: OpalBase.Address) throws -> Data {
        guard let entry = findEntry(for: address) else { throw Error.entryNotFound }
        let privateKey = try generatePrivateKey(at: entry.derivationPath.index,
                                                for: entry.derivationPath.usage)
        return privateKey
    }
    
    func derivePrivateKeys(for utxos: [OpalBase.Transaction.Output.Unspent]) throws -> [OpalBase.Transaction.Output.Unspent: Data] {
        var derived: [OpalBase.Transaction.Output.Unspent: Data] = .init()
        derived.reserveCapacity(utxos.count)
        
        var addressByLockingScript: [Data: OpalBase.Address] = .init()
        addressByLockingScript.reserveCapacity(utxos.count)
        
        var privateKeyByAddress: [OpalBase.Address: Data] = .init()
        privateKeyByAddress.reserveCapacity(utxos.count)
        
        for utxo in utxos {
            let lockingScript = utxo.lockingScript
            let address: OpalBase.Address
            if let cachedAddress = addressByLockingScript[lockingScript] {
                address = cachedAddress
            } else {
                let script = try OpalBase.Script.decode(lockingScript: lockingScript)
                address = try OpalBase.Address(script: script)
                addressByLockingScript[lockingScript] = address
            }
            
            let privateKey: Data
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
