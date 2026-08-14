// OpalBase+Address+Book+UTXORepository.swift

import Foundation

extension _OpalBase.Address.Book {
    struct UTXORepository {
        struct Outpoint: Hashable, Sendable {
            let transactionHash: OpalBase.Transaction.Hash
            let outputIndex: UInt32

            init(
                transactionHash: OpalBase.Transaction.Hash,
                outputIndex: UInt32
            ) {
                self.transactionHash = transactionHash
                self.outputIndex = outputIndex
            }
            
            init(_ input: OpalBase.Transaction.Input) {
                self.init(
                    transactionHash: input.previousTransactionHash,
                    outputIndex: input.previousTransactionOutputIndex
                )
            }
            
            init(_ utxo: OpalBase.Transaction.Output.Unspent) {
                self.init(
                    transactionHash: utxo.previousTransactionHash,
                    outputIndex: utxo.previousTransactionOutputIndex
                )
            }
        }
        
        var utxosByLockingScript: [Data: Set<OpalBase.Transaction.Output.Unspent>]
        var utxosByOutpoint: [Outpoint: OpalBase.Transaction.Output.Unspent]
        var reservedUTXOs: Set<OpalBase.Transaction.Output.Unspent>
        var mosaicQuarantinedOutpointsByOwnerIdentifier: [UUID: [UInt64: Set<Outpoint>]]
        
        init() {
            self.utxosByLockingScript = .init()
            self.utxosByOutpoint = .init()
            self.reservedUTXOs = .init()
            self.mosaicQuarantinedOutpointsByOwnerIdentifier = .init()
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
            let newOutpoints = Set(newUTXOs.map(Outpoint.init))
            
            if let oldUTXOs = utxosByLockingScript[lockingScript] {
                for utxo in oldUTXOs where newOutpoints.contains(Outpoint(utxo)) == false {
                    utxosByOutpoint.removeValue(forKey: Outpoint(utxo))
                    reservedUTXOs.remove(utxo)
                    discard(utxo)
                }
            }
            
            if newUTXOs.isEmpty {
                utxosByLockingScript.removeValue(forKey: lockingScript)
            } else {
                for utxo in newUTXOs {
                    store(utxo)
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
            mosaicQuarantinedOutpointsByOwnerIdentifier.removeAll()
        }

        mutating func quarantineMosaicOutpoints(
            _ outpoints: Set<Outpoint>,
            ownerIdentifier: UUID,
            ownerGeneration: UInt64
        ) {
            guard !outpoints.isEmpty else { return }
            var quarantinedOutpointsByGeneration =
                mosaicQuarantinedOutpointsByOwnerIdentifier[ownerIdentifier]
                ?? [:]
            quarantinedOutpointsByGeneration[ownerGeneration, default: []]
                .formUnion(outpoints)
            mosaicQuarantinedOutpointsByOwnerIdentifier[ownerIdentifier] =
                quarantinedOutpointsByGeneration
        }

        mutating func releaseMosaicOutpointQuarantine(
            ownerIdentifier: UUID,
            ownerGeneration: UInt64
        ) {
            guard var quarantinedOutpointsByGeneration =
                    mosaicQuarantinedOutpointsByOwnerIdentifier[ownerIdentifier]
            else {
                return
            }

            quarantinedOutpointsByGeneration.removeValue(
                forKey: ownerGeneration
            )
            if quarantinedOutpointsByGeneration.isEmpty {
                mosaicQuarantinedOutpointsByOwnerIdentifier.removeValue(
                    forKey: ownerIdentifier
                )
            } else {
                mosaicQuarantinedOutpointsByOwnerIdentifier[ownerIdentifier] =
                    quarantinedOutpointsByGeneration
            }
        }
        
        mutating func reserve(_ utxos: Set<OpalBase.Transaction.Output.Unspent>) throws {
            try reserve(utxos, tokenSelectionPolicy: .allowTokenUTXOs)
        }
        
        mutating func reserve(_ utxos: Set<OpalBase.Transaction.Output.Unspent>,
                              tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy) throws {
            guard containsExact(utxos, tokenSelectionPolicy: tokenSelectionPolicy) else {
                throw OpalBase.Address.Book.Error.utxoNotFound
            }
            
            if let conflict = reservedUTXOs.intersection(utxos).first {
                throw OpalBase.Address.Book.Error.utxoAlreadyReserved(conflict)
            }
            let quarantinedOutpoints = allMosaicQuarantinedOutpoints
            if let conflict = utxos.first(where: {
                quarantinedOutpoints.contains(Outpoint($0))
            }) {
                throw OpalBase.Address.Book.Error.utxoAlreadyReserved(conflict)
            }
            
            reservedUTXOs.formUnion(utxos)
        }
        
        mutating func release(_ utxos: Set<OpalBase.Transaction.Output.Unspent>) {
            guard !utxos.isEmpty else { return }
            reservedUTXOs.subtract(utxos)
        }

        mutating func releaseAllReservations() {
            reservedUTXOs.removeAll()
        }
        
        func findUTXO(matching input: OpalBase.Transaction.Input) -> OpalBase.Transaction.Output.Unspent? {
            utxosByOutpoint[Outpoint(input)]
        }

        func containsExact(_ utxos: Set<OpalBase.Transaction.Output.Unspent>) -> Bool {
            utxos.allSatisfy(containsExact)
        }

        func containsExact(
            _ utxos: Set<OpalBase.Transaction.Output.Unspent>,
            tokenSelectionPolicy: OpalBase.Address.Book.CoinSelection.TokenSelectionPolicy
        ) -> Bool {
            utxos.allSatisfy { utxo in
                guard containsExact(utxo) else {
                    return false
                }

                switch tokenSelectionPolicy {
                case .excludeTokenUTXOs:
                    return utxo.tokenData == nil
                case .allowTokenUTXOs:
                    return true
                }
            }
        }

        private func containsExact(_ utxo: OpalBase.Transaction.Output.Unspent) -> Bool {
            guard let stored = utxosByOutpoint[Outpoint(utxo)] else {
                return false
            }

            return stored.hasSameOutpointAndPayload(as: utxo)
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
            let outpoint = Outpoint(utxo)
            let storedUTXO = utxosByOutpoint.removeValue(forKey: outpoint) ?? utxo
            guard var indexedUTXOs = utxosByLockingScript[storedUTXO.lockingScript] else {
                return
            }
            
            indexedUTXOs.remove(storedUTXO)
            
            if indexedUTXOs.isEmpty {
                utxosByLockingScript.removeValue(forKey: storedUTXO.lockingScript)
            } else {
                utxosByLockingScript[storedUTXO.lockingScript] = indexedUTXOs
            }
        }
    }
}

extension _OpalBase.Address.Book.UTXORepository: Sendable {}
