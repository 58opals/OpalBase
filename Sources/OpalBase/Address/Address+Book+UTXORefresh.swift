// Address+Book+UTXORefresh.swift

import Foundation

extension Address.Book {
    public struct UTXORefresh {
        public let utxosByAddress: [Address: [Transaction.Output.Unspent]]
        public let changeSets: [UTXOChangeSet]
        public let totalBalance: Satoshi
        
        public init(utxosByAddress: [Address : [Transaction.Output.Unspent]],
                    changeSets: [UTXOChangeSet],
                    totalBalance: Satoshi) {
            self.utxosByAddress = utxosByAddress
            self.changeSets = changeSets
            self.totalBalance = totalBalance
        }
    }
}

extension Address.Book.UTXORefresh: Sendable {}
extension Address.Book.UTXORefresh: Equatable {}

extension Address.Book {
    public func refreshUTXOSet(using service: Network.AddressReadable,
                               usage: DerivationPath.Usage? = nil) async throws -> UTXORefresh {
        var refreshedUTXOs: [Address: [Transaction.Output.Unspent]] = .init()
        var changeSets: [UTXOChangeSet] = .init()
        
        let refreshTimestamp = Date.now
        try await forEachTargetUsage(usage) { _, entries in
            let addresses = entries.map(\.address)
            let usageResults = try await addresses.mapConcurrently(limit: Concurrency.Tuning.maximumConcurrentNetworkRequests) { address in
                let utxos = try await service.fetchUnspentOutputs(for: address.string)
                return (address, utxos)
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
}
