// OpalBase.Address+BookActor+Request.swift

import Foundation

extension _OpalBase.Address.Book {
    enum Request: Hashable, Sendable {
        case updateCache(usage: OpalBase.DerivationPath.UsageModel? = nil)
        case refreshBalances(usage: OpalBase.DerivationPath.UsageModel? = nil)
        case fetchBalance(OpalBase.Address)
        case refreshUTXOSet
        case fetchDetailedTransactions(scope: OpalBase.DerivationPath.UsageModel,
                                       fromHeight: UInt?,
                                       toHeight: UInt?,
                                       includeUnconfirmed: Bool)
        case fetchCombinedHistory(fromHeight: UInt?,
                                  toHeight: UInt?,
                                  includeUnconfirmed: Bool)
        case fetchCombinedHistoryPage(fromHeight: UInt?,
                                      window: UInt,
                                      includeUnconfirmed: Bool)
        case refreshUsedStatus(usage: OpalBase.DerivationPath.UsageModel? = nil)
        case updateAddressUsageStatus(usage: OpalBase.DerivationPath.UsageModel? = nil)
        case checkIfUsed(OpalBase.Address)
        case scanForUsedAddresses
    }
}
