// OpalBase+Address+Book+UTXORefresh.swift

import Foundation

extension _OpalBase.Address.Book {
    struct UTXORefresh {
        let utxosByAddress: [OpalBase.Address: [OpalBase.Transaction.Output.Unspent]]
        let changeSets: [UTXOChangeSet]
        let totalBalance: OpalBase.Satoshi
    }
}

extension _OpalBase.Address.Book.UTXORefresh: Sendable {}
extension _OpalBase.Address.Book.UTXORefresh: Equatable {}

extension _OpalBase.Address.Book {
    func refreshUTXOSet(using service: OpalBase.Network.AddressReader,
                               usage: OpalBase.Key.DerivationPath.Usage? = nil,
                               mutationPermit: OpalBase.Network.ChainRefreshMutationPermit? = nil) async throws -> UTXORefresh {
        var refreshedUTXOs: [OpalBase.Address: [OpalBase.Transaction.Output.Unspent]] = .init()
        var plannedRefreshes: [(address: OpalBase.Address, utxos: [OpalBase.Transaction.Output.Unspent])] = .init()
        var seenRefreshOutpoints: Set<UTXORepository.Outpoint> = .init()
        
        let refreshTimestamp = Date.now
        try await performForEachTargetUsage(usage) { _, entries in
            let addresses = entries.map(\.address)
            let fetchedUnspentOutputsByAddress = try await addresses.mapConcurrently { address in
                let unspentOutputs = try await service.fetchUnspentOutputs(for: address.string, tokenFilter: .include)
                return (address, unspentOutputs)
            }
            
            for (address, unspentOutputs) in fetchedUnspentOutputsByAddress {
                let changeSet = try makeUTXOChangeSet(for: address,
                                                       with: unspentOutputs,
                                                       timestamp: refreshTimestamp)
                for utxo in changeSet.updated {
                    guard seenRefreshOutpoints.insert(UTXORepository.Outpoint(utxo)).inserted else {
                        throw OpalBase.Network.Error(
                            reason: .protocolViolation,
                            message: "Unspent output response contained duplicate outpoints"
                        )
                    }
                }
                refreshedUTXOs[address] = changeSet.updated
                plannedRefreshes.append((address, changeSet.updated))
            }
        }
        
        let (changeSets, totalBalance, usedUsages) = try commitChainRefresh(using: mutationPermit) {
            let changeSets = try plannedRefreshes.map { refresh in
                try makeUTXOChangeSet(for: refresh.address, with: refresh.utxos, timestamp: refreshTimestamp)
            }
            let totalBalance = try changeSets.sumSatoshi { $0.balance }
            var usages: Set<OpalBase.Key.DerivationPath.Usage> = []
            for (refresh, changeSet) in zip(plannedRefreshes, changeSets) {
                replaceUTXOs(for: refresh.address, withValidated: refresh.utxos)
                try updateCachedBalance(for: refresh.address,
                                        balance: changeSet.balance,
                                        timestamp: refreshTimestamp)
                if !refresh.utxos.isEmpty {
                    let entry = try inventory.mark(address: refresh.address, isUsed: true)
                    usages.insert(entry.derivationPath.usage)
                }
            }
            return (changeSets, totalBalance, usages)
        }
        for usage in usedUsages { try await generateEntriesIfNeeded(for: usage) }

        return UTXORefresh(utxosByAddress: refreshedUTXOs,
                           changeSets: changeSets,
                           totalBalance: totalBalance)
    }

    func refreshUTXOSet(using service: any OpalBase.Network.AddressReadable,
                        usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        try await refreshUTXOSet(using: .init(service), usage: usage)
    }
}
