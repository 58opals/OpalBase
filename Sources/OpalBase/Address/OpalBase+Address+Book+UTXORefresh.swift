// OpalBase+Address+Book+UTXORefresh.swift

import Foundation

extension _OpalBase.Address.Book {
    struct UTXORefresh {
        let utxosByAddress: [OpalBase.Address: [OpalBase.Transaction.Output.Unspent]]
        let changeSets: [UTXOChangeSet]
        let totalBalance: OpalBase.Satoshi
        
        init(utxosByAddress: [OpalBase.Address : [OpalBase.Transaction.Output.Unspent]],
                    changeSets: [UTXOChangeSet],
                    totalBalance: OpalBase.Satoshi) {
            self.utxosByAddress = utxosByAddress
            self.changeSets = changeSets
            self.totalBalance = totalBalance
        }
    }
}

extension _OpalBase.Address.Book.UTXORefresh: Sendable {}
extension _OpalBase.Address.Book.UTXORefresh: Equatable {}

extension _OpalBase.Address.Book {
    func refreshUTXOSet(using service: OpalBase.Network.AddressReader,
                               usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        var refreshedUTXOs: [OpalBase.Address: [OpalBase.Transaction.Output.Unspent]] = .init()
        var plannedRefreshes: [(address: OpalBase.Address, utxos: [OpalBase.Transaction.Output.Unspent], changeSet: UTXOChangeSet)] = .init()
        
        let refreshTimestamp = Date.now
        try await performForEachTargetUsage(usage) { _, entries in
            let addresses = entries.map(\.address)
            let usageResults = try await addresses.mapConcurrently { address in
                let utxos = try await service.fetchUnspentOutputs(for: address.string, tokenFilter: .include)
                let lockingScript = address.lockingScript.data
                var seenOutpoints: Set<UTXORepository.Outpoint> = .init()
                for utxo in utxos {
                    guard utxo.lockingScript == lockingScript else {
                        throw OpalBase.Network.Error(
                            reason: .protocolViolation,
                            message: "Unspent output locking script does not match requested address"
                        )
                    }
                    guard seenOutpoints.insert(UTXORepository.Outpoint(utxo)).inserted else {
                        throw OpalBase.Network.Error(
                            reason: .protocolViolation,
                            message: "Unspent output response contained duplicate outpoints"
                        )
                    }
                }
                let orderedUTXOs = utxos.sorted { $0.compareOrder(before: $1) }
                return (address, orderedUTXOs)
            }
            
            for (address, utxos) in usageResults {
                refreshedUTXOs[address] = utxos
                let changeSet = try makeUTXOChangeSet(for: address,
                                                       with: utxos,
                                                       timestamp: refreshTimestamp)
                plannedRefreshes.append((address, utxos, changeSet))
            }
        }
        
        let changeSets = plannedRefreshes.map(\.changeSet)
        let totalBalance = try changeSets.sumSatoshi { $0.balance }

        for refresh in plannedRefreshes {
            replaceUTXOs(for: refresh.address, withValidated: refresh.utxos)
            try updateCachedBalance(for: refresh.address,
                                    balance: refresh.changeSet.balance,
                                    timestamp: refreshTimestamp)

            if !refresh.utxos.isEmpty {
                try await mark(address: refresh.address, isUsed: true)
            }
        }

        return UTXORefresh(utxosByAddress: refreshedUTXOs,
                           changeSets: changeSets,
                           totalBalance: totalBalance)
    }

    func refreshUTXOSet(using service: any OpalBase.Network.AddressReadable,
                        usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        try await refreshUTXOSet(using: .init(service), usage: usage)
    }
}
