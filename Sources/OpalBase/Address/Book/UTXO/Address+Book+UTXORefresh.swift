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
        let targetUsages = usage.map { [$0] } ?? DerivationPath.Usage.allCases
        var refreshedUTXOs: [Address: [Transaction.Output.Unspent]] = .init()
        var changeSets: [UTXOChangeSet] = .init()
        
        for currentUsage in targetUsages {
            let entries = listEntries(for: currentUsage)
            guard !entries.isEmpty else { continue }
            
            let usageResults = try await withThrowingTaskGroup(of: (Address, [Transaction.Output.Unspent]).self) { group -> [(Address, [Transaction.Output.Unspent]) ] in
                for entry in entries {
                    let address = entry.address
                    let addressString = address.string
                    group.addTask {
                        try Task.checkCancellation()
                        let utxos = try await service.fetchUnspentOutputs(for: addressString)
                        return (address, utxos)
                    }
                }
                
                var results: [(Address, [Transaction.Output.Unspent])] = .init()
                for try await result in group {
                    results.append(result)
                }
                return results
            }
            
            for (address, utxos) in usageResults {
                refreshedUTXOs[address] = utxos
                let timestamp = Date()
                let changeSet = try replaceUTXOs(for: address,
                                                 with: utxos,
                                                 timestamp: timestamp)
                changeSets.append(changeSet)
                
                if !utxos.isEmpty {
                    try await mark(address: address, isUsed: true)
                }
            }
        }
        
        var aggregateValue: UInt64 = 0
        for changeSet in changeSets {
            let (updated, didOverflow) = aggregateValue.addingReportingOverflow(changeSet.balance.uint64)
            if didOverflow { throw Satoshi.Error.exceedsMaximumAmount }
            aggregateValue = updated
        }
        
        let totalBalance = try Satoshi(aggregateValue)
        return UTXORefresh(utxosByAddress: refreshedUTXOs,
                           changeSets: changeSets,
                           totalBalance: totalBalance)
    }
}
