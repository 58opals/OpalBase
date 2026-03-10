// OpalBase+Address+Book+UTXORefresh.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct UTXORefresh {
        public let utxosByAddress: [OpalBase.Address: [OpalBase.Transaction.Output.Unspent]]
        public let changeSets: [UTXOChangeSet]
        public let totalBalance: OpalBase.Satoshi
        
        public init(utxosByAddress: [OpalBase.Address : [OpalBase.Transaction.Output.Unspent]],
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
    public func refreshUTXOSet(using service: OpalBase.Network.AddressReader,
                               usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        var refreshedUTXOs: [OpalBase.Address: [OpalBase.Transaction.Output.Unspent]] = .init()
        var changeSets: [UTXOChangeSet] = .init()
        
        let refreshTimestamp = Date.now
        try await performForEachTargetUsage(usage) { _, entries in
            let addresses = entries.map(\.address)
            let usageResults = try await addresses.mapConcurrently { address in
                let utxos = try await service.fetchUnspentOutputs(for: address.string, tokenFilter: .include)
                let orderedUTXOs = utxos.sorted { $0.compareOrder(before: $1) }
                return (address, orderedUTXOs)
            }
            
            for (address, utxos) in usageResults {
                refreshedUTXOs[address] = utxos
                let changeSet = try replaceUTXOs(for: address,
                                                 with: utxos,
                                                 timestamp: refreshTimestamp)
                changeSets.append(changeSet)
                
                if !utxos.isEmpty {
                    try await mark(address: address, isUsed: true)
                }
            }
        }
        
        let totalBalance = try changeSets.sumSatoshi { $0.balance }
        
        return UTXORefresh(utxosByAddress: refreshedUTXOs,
                           changeSets: changeSets,
                           totalBalance: totalBalance)
    }

    func refreshUTXOSet(using service: any OpalBase.Network.AddressReadable,
                        usage: OpalBase.Key.DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        try await refreshUTXOSet(using: .init(service), usage: usage)
    }
}
