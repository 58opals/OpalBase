// AccountActor+BalanceRefreshModel.swift

import Foundation

extension AccountActor {
    public struct BalanceRefreshModel: Sendable {
        public let balancesByUsage: [DerivationPathModel.UsageModel: [AddressModel: SatoshiModel]]
        public let total: SatoshiModel
        
        public init(balancesByUsage: [DerivationPathModel.UsageModel: [AddressModel: SatoshiModel]], total: SatoshiModel) {
            self.balancesByUsage = balancesByUsage
            self.total = total
        }
    }
}

extension AccountActor {
    public func refreshBalances(for usage: DerivationPathModel.UsageModel? = nil,
                                loader: @escaping @Sendable (AddressModel) async throws -> SatoshiModel) async throws -> BalanceRefreshModel {
        let targetUsages = DerivationPathModel.UsageModel.resolveTargetUsages(for: usage)
        var balancesByUsage: [DerivationPathModel.UsageModel: [AddressModel: SatoshiModel]] = .init()
        let refreshTimestamp = Date.now
        
        for currentUsage in targetUsages {
            let entries = await addressBook.listEntries(for: currentUsage)
            
            guard !entries.isEmpty else {
                balancesByUsage[currentUsage] = .init()
                continue
            }
            
            let addresses = entries.map(\.address)
            let usageResults = try await addresses.mapConcurrently(
                transformError: { address, error in
                    Error.balanceRefreshFailed(address, error)
                }
            ) { address in
                let balance = try await loader(address)
                return (address, balance)
            }
            
            let usageBalances = Dictionary(uniqueKeysWithValues: usageResults)
            
            try await mapAddressBookError {
                try await addressBook.updateCachedBalances(usageBalances, timestamp: refreshTimestamp)
            }
            balancesByUsage[currentUsage] = usageBalances
        }
        
        let total = try balancesByUsage.values.reduce(SatoshiModel()) { partial, balances in
            let usageTotal = try balances.values.sumSatoshi(or: Error.paymentExceedsMaximumAmount)
            return try partial + usageTotal
        }
        
        return BalanceRefreshModel(balancesByUsage: balancesByUsage, total: total)
    }
}
