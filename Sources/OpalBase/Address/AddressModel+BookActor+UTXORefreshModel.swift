// AddressModel+BookActor+UTXORefreshModel.swift

import Foundation

extension AddressModel.BookActor {
    public struct UTXORefreshModel {
        public let utxosByAddress: [AddressModel: [TransactionModel.OutputModel.UnspentModel]]
        public let changeSets: [UTXOChangeSetModel]
        public let totalBalance: SatoshiModel
        
        public init(utxosByAddress: [AddressModel : [TransactionModel.OutputModel.UnspentModel]],
                    changeSets: [UTXOChangeSetModel],
                    totalBalance: SatoshiModel) {
            self.utxosByAddress = utxosByAddress
            self.changeSets = changeSets
            self.totalBalance = totalBalance
        }
    }
}

extension AddressModel.BookActor.UTXORefreshModel: Sendable {}
extension AddressModel.BookActor.UTXORefreshModel: Equatable {}

extension AddressModel.BookActor {
    public func refreshUTXOSet(using service: NetworkModel.AddressReadable,
                               usage: DerivationPathModel.UsageModel? = nil) async throws -> UTXORefreshModel {
        var refreshedUTXOs: [AddressModel: [TransactionModel.OutputModel.UnspentModel]] = .init()
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
