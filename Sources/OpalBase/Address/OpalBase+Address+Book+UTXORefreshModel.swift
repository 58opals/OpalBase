// OpalBase.Address+BookActor+UTXORefreshModel.swift

import Foundation

extension _OpalBase.Address.Book {
    public struct UTXORefreshModel {
        public let utxosByAddress: [OpalBase.Address: [OpalBase.Transaction.OutputModel.UnspentModel]]
        public let changeSets: [UTXOChangeSetModel]
        public let totalBalance: OpalBase.Satoshi
        
        public init(utxosByAddress: [OpalBase.Address : [OpalBase.Transaction.OutputModel.UnspentModel]],
                    changeSets: [UTXOChangeSetModel],
                    totalBalance: OpalBase.Satoshi) {
            self.utxosByAddress = utxosByAddress
            self.changeSets = changeSets
            self.totalBalance = totalBalance
        }
    }
}

extension _OpalBase.Address.Book.UTXORefreshModel: Sendable {}
extension _OpalBase.Address.Book.UTXORefreshModel: Equatable {}

extension _OpalBase.Address.Book {
    public func refreshUTXOSet(using service: OpalBase.Network.AddressReadable,
                               usage: OpalBase.DerivationPath.UsageModel? = nil) async throws -> UTXORefreshModel {
        var refreshedUTXOs: [OpalBase.Address: [OpalBase.Transaction.OutputModel.UnspentModel]] = .init()
        var changeSets: [UTXOChangeSetModel] = .init()
        
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
        
        return UTXORefreshModel(utxosByAddress: refreshedUTXOs,
                           changeSets: changeSets,
                           totalBalance: totalBalance)
    }
}
